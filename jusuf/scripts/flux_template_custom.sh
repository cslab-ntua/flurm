#!/bin/bash -l

#SBATCH --job-name=flux-custom-test
#SBATCH --output=/p/home/jusers/%u/jusuf/tests/flux-custom-test-%j.out
#SBATCH --error=/p/home/jusers/%u/jusuf/tests/flux-custom-test-%j.err
#SBATCH --nodes=2
#SBATCH --ntasks=256
#SBATCH --threads-per-core=1
#SBATCH --time=00:10:00
#SBATCH --partition=batch
#SBATCH --account=seanergys
#SBATCH --exclusive
#SBATCH --disable-turbomode

set -eo pipefail

# Usage: sbatch flux_template_custom.sh [CORE_VERSION] [SCHED_VERSION]
# Versions must match an installation produced by install_flux_custom.sh.
CORE_VERSION="${1:-${CORE_VERSION:-0.85.0-cosched}}"
SCHED_VERSION="${2:-${SCHED_VERSION:-0.53-moldable-config}}"
CORE_VERSION="${CORE_VERSION#v}"
SCHED_VERSION="${SCHED_VERSION#v}"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"

## LOAD MODULES AND CUSTOM FLUX ##
module purge
module load GCCcore/14.3.0
module load git/2.50.1
module load Python/3.13.5

: "${PROJECT_seanergys:?PROJECT_seanergys is not set}"
: "${USER:?USER is not set}"
FLURM_DIR="$PROJECT_seanergys/$USER/flurm"
HOME_FLURM_DIR="$HOME/flurm"

# Spack expects the Python executable, rather than its installation prefix.
export SPACK_PYTHON="$(command -v python3)"

CUSTOM_ENV="$FLURM_DIR/custom-flux-envs/core-${CORE_VERSION}_sched-${SCHED_VERSION}_gcc13"
if [[ ! -r "$CUSTOM_ENV/load.sh" ]]; then
    printf 'Custom Flux loader not found: %s/load.sh\n' "$CUSTOM_ENV" >&2
    printf 'Install this release pair with install_flux_custom.sh first.\n' >&2
    exit 1
fi

# This also sets the scheduler modprobe path needed to start Fluxion.
source "$CUSTOM_ENV/load.sh"
printf 'Custom Flux environment: %s\n' "$CUSTOM_ENV"
command -v flux
flux version

## RUN YOUR PROGRAM ##
readarray -t HOSTS < <(scontrol show hostnames "$SLURM_NODELIST")
CONTROL_NODE=${HOSTS[0]}
COMPUTE_NODES=("${HOSTS[@]:1}")

echo "Control node: $CONTROL_NODE"
echo "Compute nodes: ${COMPUTE_NODES[*]}"

COMPUTE_NODELIST=$(IFS=, ; echo "${COMPUTE_NODES[*]}")
COMPUTE_RLIST=$(printf '"%s",' "${COMPUTE_NODES[@]}")
COMPUTE_RLIST=${COMPUTE_RLIST%,}
NNODES=$((SLURM_JOB_NUM_NODES-1))
SOCKETS_PER_NODE=2
NUMA_PER_SOCKET=4
CCD_PER_NUMA=2
CORES_PER_CCD=8
CORES_PER_NODE=$((CORES_PER_CCD * CCD_PER_NUMA * NUMA_PER_SOCKET * SOCKETS_PER_NODE))
CUSTOM_TEST_TIMEOUT="${CUSTOM_TEST_TIMEOUT:-120}"

RANKLIST="0-$NNODES"
if [ "$NNODES" -eq 0 ]; then
    RANKLIST="0"
fi

echo "Compute Rlist: $COMPUTE_RLIST"

uuid=$(uuidgen)
timestamp=$(date +%s)
nodefile="${uuid}_${timestamp}"

path="$FLURM_DIR/conf.d/$nodefile/R"
scheduling="$FLURM_DIR/conf.d/$nodefile/aris.json"
mkdir -p "$FLURM_DIR/conf.d/$nodefile"

python3 "$HOME_FLURM_DIR/scripts/jgf_gen.py" \
    --nodes "$CONTROL_NODE,$COMPUTE_NODELIST" \
    --set "socket=$SOCKETS_PER_NODE" \
    --set "numanode=$NUMA_PER_SOCKET" \
    --set "ccd=$CCD_PER_NUMA" \
    --set "core=$CORES_PER_CCD" \
    -o "$scheduling"

flux R encode -H "$CONTROL_NODE,$COMPUTE_NODELIST" \
    -c "0-$((CORES_PER_NODE - 1))" > "$path"
sed -e "s|PATH|\"${path}\"|g" \
    -e "s|SCHEDULING|\"${scheduling}\"|g" \
    "$HOME_FLURM_DIR/conf.d/flux-config-custom.toml" \
    > "$FLURM_DIR/conf.d/$nodefile/flux-config-custom.toml"

TEST_LOG_DIR="$FLURM_DIR/conf.d/$nodefile/installation-check"
printf 'Installation check logs: %s\n' "$TEST_LOG_DIR"

srun -N "$SLURM_JOB_NUM_NODES" -n "$SLURM_JOB_NUM_NODES" \
    --mpi=pmi2 --cpu-bind=none --export=ALL \
    flux start -o --config-path="$FLURM_DIR/conf.d/$nodefile/flux-config-custom.toml" \
    bash "$HOME_FLURM_DIR/scripts/test_custom_installation.sh" \
    "$TEST_LOG_DIR" "$CUSTOM_TEST_TIMEOUT"
    
