#!/bin/bash

module load gnu/8
module load gnu/13.2.0
module load python/3.9.18
module load git
module load zlib
module load rust

export SPACK_PYTHON="$(dirname "$(dirname "$(which python)")")"
git clone --depth=2 --branch releases/v1.0 https://github.com/spack/spack.git
export SPACK_USER_CACHE_PATH=$(pwd)/.spack     #/path/to/.spack default is ~/.spack
export SPACK_USER_CONFIG_PATH=$(pwd)/.spack    #/path/to/.spack default is ~/.spack
. spack/share/spack/setup-env.sh

spack config add config:verify_ssl:false 
# Find external compilers, libraries and the python interpreter
spack compiler add /apps/compilers/gnu/13.2.0
spack external find rust
spack external find python
spack external find zlib
# We do not need to build rust in spack
spack config add packages:rust:buildable:false
# Flags and external library paths that spack misses by default
sed -i '284i \
            current_environment["LDFLAGS"] = "-lrt"\
            current_environment["PYO3_USE_ABI3_FORWARD_COMPATIBILITY"] = "1"\
            existing = current_environment.get("LD_LIBRARY_PATH", "")\
            current_environment["LD_LIBRARY_PATH"] = f"/apps/libraries/zlib/1.2.11/lib:/apps/compilers/gnu/13.2.0/lib:/apps/compilers/gnu/13.2.0/lib64:/apps/applications/python/3.9.18/lib:{existing}"' \
spack/lib/spack/spack/util/executable.py
# Finally install flux
CORE=$(find $SPACK_USER_CONFIG_PATH/package_repos -name flux_core)
SCHED=$(find $SPACK_USER_CONFIG_PATH/package_repos -name flux_sched)
sed -i '25i \
    version("0.78.0", sha256="9159ccb64826b23391abe7c125a9e2ccaa1eb6409eeb2fd2a6ee4be07bf39e56")' \
$CORE/package.py
sed -i '25i \
    version("0.47.0", sha256="80194e5c23e7ef5f4bf6cb1c9f63f949f979e9f58c7976e5453c31f244d3fd6a")' \
$SCHED/package.py

spack install --yes-to-all flux-core@0.78
spack install --yes-to-all flux-sched@0.47