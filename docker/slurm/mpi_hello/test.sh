#!/bin/bash
#SBATCH --job-name=my_mpi_job        # Job name
#SBATCH --output=my_mpi_job_%j.out  # Output file name (%j expands to jobID)
#SBATCH --error=my_mpi_job_%j.err   # Error file name (%j expands to jobID)
#SBATCH --partition=normal          # Partition name
#SBATCH --nodes=2                    # Number of nodes
#SBATCH --ntasks-per-node=2          # Number of tasks per node
#SBATCH --cpus-per-task=1          # Number of tasks per node
#SBATCH --time=00:10:00              # Time limit (HH:MM:SS)

# needed for docker version
export PSM3_HAL=loopback

# Run MPI application
mpirun -np 4 /home/slurm/mpi_hello/mpi_hello
