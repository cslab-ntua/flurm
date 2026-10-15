#!/bin/bash -l

GIT_VERSION="${1:-2.47.3}"

PREFIX=$(pwd)
SRC_DIR="$(pwd)/src"
TARBALL="git-${GIT_VERSION}.tar.xz"
URL="https://mirrors.edge.kernel.org/pub/software/scm/git/${TARBALL}"

mkdir -p "$SRC_DIR"

cd "$SRC_DIR"

echo "Downloading Git $GIT_VERSION..."
if [ ! -f "$TARBALL" ]; then
    curl -LO "$URL"
fi

echo "Extracting..."
rm -rf "git-${GIT_VERSION}"
tar -xf "$TARBALL"

cd "git-${GIT_VERSION}"

echo "Configuring with prefix: $PREFIX"
make configure
./configure --prefix="$PREFIX"

echo "Building..."
make -j"$(nproc)"

echo "Installing..."
make install

echo
echo "Git installed to: $PREFIX"