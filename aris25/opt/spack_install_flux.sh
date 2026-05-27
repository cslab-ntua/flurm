#!/bin/bash

module purge
git clone --depth=2 https://github.com/spack/spack.git
export SPACK_USER_CACHE_PATH=$(pwd)/.spack     #/path/to/.spack default is ~/.spack
export SPACK_USER_CONFIG_PATH=$(pwd)/.spack    #/path/to/.spack default is ~/.spack
export SPACK_STAGE=$(pwd)/spack_stage
. spack/share/spack/setup-env.sh

spack config add config:build_stage/$SPACK_STAGE
spack install gcc@13
spack compiler find
spack install flux-sched@0.48.0%gcc