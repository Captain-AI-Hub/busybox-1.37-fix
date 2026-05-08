#!/bin/bash
set -euo pipefail

mkdir -p multi-gcc
cd multi-gcc

BASE="https://toolchains.bootlin.com/downloads/releases/toolchains"

for arch in \
    aarch64 \
    armv7-eabihf \
    mips32 \
    mips32el \
    mips64el-n32 \
    mips64-n32 \
    riscv32-ilp32d \
    riscv64-lp64d \
    x86-64 \
    x86-i686; do

    tarball="$arch--glibc--stable-2025.08-1.tar.xz"
    url="$BASE/$arch/tarballs/$tarball"

    if [ -f "$tarball" ]; then
        echo "Skipping $tarball (already exists)"
        continue
    fi

    echo "Downloading $tarball ..."
    wget -q --show-progress "$url"
done

echo "Extracting toolchains ..."
for f in *.tar.xz; do
    tar -xJf "$f"
done

echo "Cleaning up tarballs ..."
rm -f *.tar.xz

echo "Done. Toolchains installed in $(pwd)"
