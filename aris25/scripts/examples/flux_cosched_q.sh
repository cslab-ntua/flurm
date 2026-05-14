#!/bin/bash -l

#SBATCH --job-name=FluxTest    # Job name
#SBATCH --output=/users/pa23/goumas/kkats/jobs/FluxTest.%j.out # Stdout (%j expands to jobId)
#SBATCH --error=/users/pa23/goumas/kkats/jobs/FluxTest.%j.err # Stderr (%j expands to jobId)
#SBATCH --ntasks=5     # Number of tasks(processes)
#SBATCH --nodes=5     # Number of nodes requested
#SBATCH --exclusive


if [ x$SLURM_CPUS_PER_TASK == x ]; then
  export OMP_NUM_THREADS=1
else
  export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
fi


## LOAD MODULES ##
module purge        # clean up loaded modules 

# load necessary modules

module load gnu/8
module load gnu/13.2.0
module load python/3.9.18
module load git
module load intel/18
module load intelmpi/2018

BASE_DIR=$HOME/kkats/flurm/aris25

export SPACK_PYTHON="$(dirname "$(dirname "$(which python)")")"
export SPACK_USER_CACHE_PATH=$BASE_DIR/opt/.spack
export SPACK_USER_CONFIG_PATH=$BASE_DIR/opt/.spack

. $BASE_DIR/opt/spack/share/spack/setup-env.sh

spack load flux-sched@0.48

## RUN YOUR PROGRAM ##
if [ "$SLURM_JOB_NUM_NODES" -lt 3 ]; then
  echo "Error: not enough nodes for partition, we need at least 3 slurm nodes" >&2
  exit 1
fi

readarray -t HOSTS < <(scontrol show hostnames $SLURM_NODELIST)
CONTROL_NODE=${HOSTS[0]}
COMPUTE_NODES=("${HOSTS[@]:1}")

echo "Control node: $CONTROL_NODE"
echo "Compute nodes: ${COMPUTE_NODES[@]}"


COMPUTE_NODELIST=$(IFS=, ; echo "${COMPUTE_NODES[*]}")
COMPUTE_RLIST=$(printf   '"%s",' "${COMPUTE_NODES[@]}"); COMPUTE_RLIST=${COMPUTE_RLIST%,}
NNODES=$((SLURM_JOB_NUM_NODES-1))
SOCKETS_PER_NODE=2
NUMA_PER_SOCKET=1
CORES_PER_NUMA=10
CORES_PER_NODE=$((CORES_PER_NUMA * NUMA_PER_SOCKET * SOCKETS_PER_NODE))
NTASKS=20

half=$(( SLURM_JOB_NUM_NODES / 2 ))
first_half=( "${COMPUTE_NODES[@]:0:half}" )
second_half=( "${COMPUTE_NODES[@]:half}" )
prop_args=()
for host in "${first_half[@]}"; do
  prop_args+=( "--prop" "${host}:normal" )
done
for host in "${second_half[@]}"; do
  prop_args+=( "--prop" "${host}:cosched" )
done

RANKLIST="0-$NNODES"
RL1="1-$half"
RL2="$(( half + 1))-$NNODES"

if (( half == 1 )); then
  RL1="1"
fi

if (( half + 1 == NNODES )); then
  RL2="$NNODES"
fi

echo "Compute Rlist: $COMPUTE_RLIST"

uuid=$(uuidgen)
timestamp=$(date +%s)
nodefile="$uuid_$timestamp"

path=$BASE_DIR/conf.d/$nodefile/R
scheduling=$BASE_DIR/conf.d/$nodefile/aris.json
# unique config directory for this job
mkdir -p "$BASE_DIR/conf.d/$nodefile/plugins/cli"

python3 $BASE_DIR/scripts/jgf_gen.py --nodes "$CONTROL_NODE,$COMPUTE_NODELIST" --set "socket=$SOCKETS_PER_NODE" --set "numanode=$NUMA_PER_SOCKET" --set "core=$CORES_PER_NUMA" "${prop_args[@]}" -o "$BASE_DIR/conf.d/$nodefile/aris.json"

flux R encode -H "$CONTROL_NODE,$COMPUTE_NODELIST" -c "0-$((CORES_PER_NODE - 1))" -p "normal:${RL1}" -p "cosched:${RL2}"
    > "$BASE_DIR/conf.d/$nodefile/R" 
sed -e "s|PATH|\"${path}\"|g" \
    -e "s|SCHEDULING|\"${scheduling}\"|g" $BASE_DIR/conf.d/flux-config.queues.toml > "$BASE_DIR/conf.d/$nodefile/flux-config.toml"

cp $BASE_DIR/conf.d/plugins/cli/* $BASE_DIR/conf.d/$nodefile/plugins/cli/

FLUX_CLI_PLUGINPATH=$BASE_DIR/conf.d/$nodefile/plugins/cli \
    srun -N $SLURM_JOB_NUM_NODES -n $SLURM_JOB_NUM_NODES --mpi=pmi2 --export=ALL flux start -o --config-path=$BASE_DIR/conf.d/$nodefile/flux-config.toml \
    bash -c "flux queue start -a && flux run --requires=\"-hosts:${CONTROL_NODE}\" -n $NTASKS --cosched $BASE_DIR/scripts/examples/mpi_hello"