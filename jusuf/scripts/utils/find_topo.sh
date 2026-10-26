#!/bin/bash -l

#SBATCH --job-name=find-topology
#SBATCH --output=/p/home/jusers/%u/jusuf/find-topology-%j.out
#SBATCH --error=/p/home/jusers/%u/jusuf/find-topology-%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --partition=batch
#SBATCH --account=seanergys
#SBATCH --exclusive
#SBATCH --disable-turbomode

numactl --hardware

lscpu -e=CPU,SOCKET,NODE,CORE,CACHE

lstopo
