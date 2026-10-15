#!/bin/bash -l

#SBATCH --job-name=SimpleFluxTest    # Job name
#SBATCH --output=/users/pa23/goumas/kkats/jobs/SimpleFluxTest.%j.out # Stdout (%j expands to jobId)
#SBATCH --error=/users/pa23/goumas/kkats/jobs/SimpleFluxTest.%j.err # Stderr (%j expands to jobId)
#SBATCH --ntasks=3     # Number of tasks(processes)
#SBATCH --nodes=3     # Number of nodes requested
#SBATCH --ntasks-per-node=1     # Tasks per node
#SBATCH --cpus-per-task=1     # Threads per task
#SBATCH --time=00:01:00   # walltime
#SBATCH --mem-per-cpu=2400
#SBATCH --exclusive

if [ x$SLURM_CPUS_PER_TASK == x ]; then
  export OMP_NUM_THREADS=1
else
  export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
fi


## LOAD MODULES ##
ps -ef | grep flux

ps -ef | grep flux | grep -v grep | awk '{print $2}' | xargs -r kill -9

ps -ef | grep flux
