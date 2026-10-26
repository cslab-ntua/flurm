#!/bin/bash -l

#SBATCH --job-name=test-cpu
#SBATCH --output=/p/home/jusers/%u/jusuf/%x-%j.out
#SBATCH --error=/p/home/jusers/%u/jusuf/%x-%j.err
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --time=00:10:00
#SBATCH --partition=batch
#SBATCH --account=seanergys
#SBATCH --exclusive
#SBATCH --disable-turbomode

echo "=== Binding disabled ==="
srun -N2 -n2 --mpi=pmi2 --cpu-bind=none bash -c \
  'hostname; grep Cpus_allowed_list /proc/self/status'

echo "\n=== Default binding ==="
srun -N2 -n2 --mpi=pmi2 bash -c \
  'hostname; grep Cpus_allowed_list /proc/self/status'