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

BASE_DIR=$HOME/kkats/flurm/aris

export SPACK_PYTHON="$(dirname "$(dirname "$(which python)")")"
export SPACK_USER_CACHE_PATH=$BASE_DIR/opt/.spack
export SPACK_USER_CONFIG_PATH=$BASE_DIR/opt/.spack

. $BASE_DIR/opt/spack/share/spack/setup-env.sh

spack load flux-sched

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

# unique config directory for this job
mkdir -p "$BASE_DIR/conf.d/$nodefile/plugins/cli"
prop_args=()
for host in "${COMPUTE_NODES[@]}"; do
  prop_args+=( "--prop" "${host}:cosched" )
done
python3 $BASE_DIR/scripts/jgf_gen.py --nodes "$CONTROL_NODE,$COMPUTE_NODELIST" --sockets 2 --cores 10 "${prop_args[@]}" -o "$BASE_DIR/conf.d/$nodefile/aris.json"

sed -e "s|TEMPLATE_HOSTLIST|\"$CONTROL_NODE\",$COMPUTE_RLIST|g" \
    -e "s|TEMPLATE_RANKLIST|${RANKLIST}|g" \
    -e "s|TEMPLATE_PROPERTIES|\"normal\" : \"${RL1}\" , \"cosched\" : \"${RL2}\"|g" \
    $BASE_DIR/conf.d/R.queues.template > "$BASE_DIR/conf.d/$nodefile/R" 
sed -e "s|NODEFILE|${nodefile}|g" $BASE_DIR/conf.d/flux-config.queues.toml > "$BASE_DIR/conf.d/$nodefile/flux-config.toml"

cp $BASE_DIR/conf.d/plugins/cli/* $BASE_DIR/conf.d/$nodefile/plugins/cli/

FLUX_DISABLE_JOB_CLEANUP=1 FLUX_CLI_PLUGINPATH=$BASE_DIR/conf.d/$nodefile/plugins/cli LD_PRELOAD=$BASE_DIR/opt/flux_helpers/redirect_random.so \
    srun -N $SLURM_JOB_NUM_NODES -n $SLURM_JOB_NUM_NODES --mpi=pmi2 --export=ALL flux start -o --config-path=$BASE_DIR/conf.d/$nodefile/flux-config.toml \
    bash -c "flux queue start -a && flux run --requires=\"-hosts:${CONTROL_NODE}\" -n $NTASKS --cosched $BASE_DIR/scripts/examples/mpi_hello"