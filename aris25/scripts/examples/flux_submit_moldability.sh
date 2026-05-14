#!/bin/bash -l

#SBATCH --job-name=FluxNAS    # Job name
#SBATCH --output=/users/pa23/goumas/kkats/jobs/FluxNAS.%j.out # Stdout (%j expands to jobId)
#SBATCH --error=/users/pa23/goumas/kkats/jobs/FluxNAS.%j.err # Stderr (%j expands to jobId)
#SBATCH --exclusive
#SBATCH --nodes=14
#SBATCH --ntasks=14
#SBATCH --time=00:10:00


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

spack load flux-sched@0.48.0-moldability

## RUN YOUR PROGRAM ##
readarray -t HOSTS < <(scontrol show hostnames $SLURM_NODELIST)
CONTROL_NODE=${HOSTS[0]}
COMPUTE_NODES=("${HOSTS[@]:1}")

echo "Control node: $CONTROL_NODE"
echo "Compute nodes: ${COMPUTE_NODES[@]}"

uuid=$(uuidgen)
timestamp=$(date +%s)
nodefile="$uuid_$timestamp"

cp $BASE_DIR/conf.d/flux-config-moldability.toml > "$BASE_DIR/conf.d/$nodefile/flux-config.toml"


srun -N $SLURM_JOB_NUM_NODES -n $SLURM_JOB_NUM_NODES --mpi=pmi2 --export=ALL flux start -o --config-path=$BASE_DIR/conf.d/$nodefile/flux-config.toml \
  flux_moldability_NAS.sh $CONTROL_NODE