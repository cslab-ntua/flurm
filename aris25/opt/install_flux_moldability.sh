#!/bin/bash

module load gnu/8
module load gnu/13.2.0
module load python/3.9.18
module load git
module load zlib
module load rust

export SPACK_PYTHON="$(dirname "$(dirname "$(which python)")")"
export SPACK_USER_CACHE_PATH=$(pwd)/.spack     #/path/to/.spack default is ~/.spack
export SPACK_USER_CONFIG_PATH=$(pwd)/.spack    #/path/to/.spack default is ~/.spack
. spack/share/spack/setup-env.sh


SCHED=$(find $SPACK_USER_CONFIG_PATH/package_repos -name flux_sched)
sed -i '25i \
    version("0.48.0-moldability", sha256="e2de46f4217355e5e6ce80d56532283097a8cfee4bd87123250ecd8900d91708")' \
$SCHED/package.py
sed -i '139i \
        if str(version) == "0.48.0-moldability": \
            return "https://github.com/kostiscpp/flux-sched/releases/download/v0.48.0-moldability/flux-sched-moldability.zip"' \
$SCHED/package.py

spack install --yes-to-all flux-core@0.48.0-moldability