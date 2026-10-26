#!/bin/bash

set -eo pipefail
: "${PROJECT_seanergys:?PROJECT_seanergys is not set}"
: "${USER:?USER is not set}"

module purge

FLURM_DIR="$PROJECT_seanergys/$USER/flurm"
mkdir -p "$FLURM_DIR"
cd "$FLURM_DIR"

git clone --depth=2 https://github.com/spack/spack.git

export SPACK_USER_CACHE_PATH="$PWD/.spack"     #/path/to/.spack default is ~/.spack
export SPACK_USER_CONFIG_PATH="$PWD/.spack"    #/path/to/.spack default is ~/.spack
export SPACK_STAGE="$PWD/spack_stage"
source spack/share/spack/setup-env.sh

spack config --scope=user add "config:build_stage:$SPACK_STAGE"
spack config get config
spack compiler find
spack install gcc@13
spack compiler find
spack install 'flux-sched@0.55.0%gcc@13'
spack find -l flux-sched
