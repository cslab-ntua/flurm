#!/bin/bash
#SBATCH --job-name=flux_job        # Job name
#SBATCH --output=/home/slurm/flux_job_%j.out  # Output file name (%j expands to jobID)
#SBATCH --error=/home/slurm/flux_job_%j.err   # Error file name (%j expands to jobID)
#SBATCH --nodes=3                    # Number of nodes
#SBATCH --time=00:10:00              # Time limit (HH:MM:SS)

# needed for docker version
export PSM3_HAL=loopback

if [ x$SLURM_CPUS_PER_TASK == x ]; then
  export OMP_NUM_THREADS=1
else
  export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
fi

. /home/spack/share/spack/setup-env.sh

spack load flux-core 

readarray -t HOSTS < <(scontrol show hostnames $SLURM_NODELIST)
CONTROL_NODE=${HOSTS[0]}
COMPUTE_NODES=("${HOSTS[@]:1}")
echo "Broker node: $CONTROL_NODE"
echo "Compute nodes: ${COMPUTE_NODES[@]}"

if [[ "$(hostname -s)" == "$CONTROL_NODE" ]]; then
    spack load flux-sched
fi


COMPUTE_NODELIST=$(IFS=, ; echo "${COMPUTE_NODES[*]}")

## RUN YOUR PROGRAM ##

srun -N 3 -n 3 --mpi=pmi2 --label --export=ALL flux start flux run -N 2 --requires="hosts:${COMPUTE_NODELIST}" hostname
