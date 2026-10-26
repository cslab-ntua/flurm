#!/bin/bash -l

#SBATCH --job-name=flux-test
#SBATCH --output=/p/home/jusers/%u/jusuf/tests/flux-test-%j.out
#SBATCH --error=/p/home/jusers/%u/jusuf/tests/flux-test-%j.err
#SBATCH --nodes=2
#SBATCH --ntasks=256
#SBATCH --threads-per-core=1
#SBATCH --time=00:10:00
#SBATCH --partition=batch
#SBATCH --account=seanergys
#SBATCH --exclusive
#SBATCH --disable-turbomode

if [ x$SLURM_CPUS_PER_TASK == x ]; then
  export OMP_NUM_THREADS=1
else
  export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
fi


## LOAD MODULES ##
module purge

module load GCCcore/14.3.0
module load git/2.50.1
module load Python/3.13.5

FLURM_DIR="$PROJECT_seanergys/$USER/flurm"

export SPACK_PYTHON="$(dirname "$(dirname "$(which python)")")"
export SPACK_USER_CACHE_PATH="$FLURM_DIR/.spack"
export SPACK_USER_CONFIG_PATH="$FLURM_DIR/.spack"

source "$FLURM_DIR/spack/share/spack/setup-env.sh"

spack load flux-sched@0.55

## RUN YOUR PROGRAM ##
readarray -t HOSTS < <(scontrol show hostnames $SLURM_NODELIST)
CONTROL_NODE=${HOSTS[0]}
COMPUTE_NODES=("${HOSTS[@]:1}")

echo "Control node: $CONTROL_NODE"
echo "Compute nodes: ${COMPUTE_NODES[@]}"

COMPUTE_NODELIST=$(IFS=, ; echo "${COMPUTE_NODES[*]}")
COMPUTE_RLIST=$(printf   '"%s",' "${COMPUTE_NODES[@]}"); COMPUTE_RLIST=${COMPUTE_RLIST%,}
NNODES=$((SLURM_JOB_NUM_NODES-1))
SOCKETS_PER_NODE=2
NUMA_PER_SOCKET=4
CCD_PER_NUMA=2
CORES_PER_CCD=8
CORES_PER_NODE=$((CORES_PER_CCD * CCD_PER_NUMA * NUMA_PER_SOCKET * SOCKETS_PER_NODE))
NTASKS=20

RANKLIST="0-$NNODES"
if [ "$NNODES" -eq 0 ]; then
  RANKLIST="0"
fi

echo "Compute Rlist: $COMPUTE_RLIST"

uuid=$(uuidgen)
timestamp=$(date +%s)
nodefile="${uuid}_${timestamp}"

HOME_FLURM_DIR="$HOME/flurm"
path="$FLURM_DIR/conf.d/$nodefile/R"
scheduling="$FLURM_DIR/conf.d/$nodefile/aris.json"

python3 "$HOME_FLURM_DIR/scripts/jgf_gen.py" \
    --nodes "$CONTROL_NODE,$COMPUTE_NODELIST" \
    --set "socket=$SOCKETS_PER_NODE" \
    --set "numanode=$NUMA_PER_SOCKET" \
    --set "ccd=$CCD_PER_NUMA" \
    --set "core=$CORES_PER_CCD" \
    -o "$scheduling"

flux R encode -H "$CONTROL_NODE,$COMPUTE_NODELIST" -c "0-$((CORES_PER_NODE - 1))" > "$FLURM_DIR/conf.d/$nodefile/R"
sed -e "s|PATH|\"${path}\"|g" \
    -e "s|SCHEDULING|\"${scheduling}\"|g" "$HOME_FLURM_DIR/conf.d/flux-config.toml" > "$FLURM_DIR/conf.d/$nodefile/flux-config.toml"

srun -N $SLURM_JOB_NUM_NODES -n $SLURM_JOB_NUM_NODES \
  --mpi=pmi2 --cpu-bind=none --export=ALL \
  flux start -o --config-path="$FLURM_DIR/conf.d/$nodefile/flux-config.toml" \
    flux run --requires="-hosts:${CONTROL_NODE}" -n $NTASKS -o cpu-affinity=per-task \
    hostname # replace with your script		
