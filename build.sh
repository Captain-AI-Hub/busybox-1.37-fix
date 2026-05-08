#!/bin/bash
set -euo pipefail

SRC_DIR="busybox-1.37.0"
INSTALL_BASE="busybox_install"
OUTPUT_DIR="busybox_static"
TOOLCHAIN_ROOT="$HOME/multi-gcc"
TOOLCHAIN_SUFFIX="--glibc--stable-2025.08-1"

mkdir -p "$OUTPUT_DIR" "$INSTALL_BASE"

set_config() {
    local name="$1"
    local value="$2"
    local tmp_config

    tmp_config=$(mktemp .config.XXXXXX)
    awk -v name="$name" 'index($0, name "=") != 1 && $0 != "# " name " is not set"' .config > "$tmp_config"
    printf '%s=%s\n' "$name" "$value" >> "$tmp_config"
    mv "$tmp_config" .config
}

unset_config() {
    local name="$1"
    local tmp_config

    tmp_config=$(mktemp .config.XXXXXX)
    awk -v name="$name" 'index($0, name "=") != 1 && $0 != "# " name " is not set"' .config > "$tmp_config"
    printf '# %s is not set\n' "$name" >> "$tmp_config"
    mv "$tmp_config" .config
}

declare -A ARCH_MAP=(
    ["aarch64"]="arm64"
    ["armv7-eabihf"]="arm"
    ["mips32el"]="mipsel"
    ["mips32"]="mips"
    ["mips64el-n32"]="mips64el-n32"
    ["mips64-n32"]="mips64-n32"
    ["riscv32-ilp32d"]="riscv32"
    ["riscv64-lp64d"]="riscv64"
    ["x86-64"]="x86_64"
    ["x86-i686"]="i686"
)

ARCH_KEYS=(
    "aarch64"
    "x86-64"
    "armv7-eabihf"
    "mips32el"
    "mips32"
    "mips64el-n32"
    "mips64-n32"
    "riscv32-ilp32d"
    "riscv64-lp64d"
    "x86-i686"
)

for arch_key in "${ARCH_KEYS[@]}"; do
    tc_dir="$TOOLCHAIN_ROOT/$arch_key$TOOLCHAIN_SUFFIX"
    out_arch=${ARCH_MAP[$arch_key]}

    if [ ! -d "$tc_dir" ]; then
        echo "Skipping $arch_key: toolchain not found: $tc_dir"
        continue
    fi

    gcc_path=$(compgen -G "$tc_dir/bin/*-linux-gcc" | sort | head -n1 || true)
    if [ ! -x "$gcc_path" ]; then
        echo "Skipping $arch_key: no gcc found"
        continue
    fi

    gcc_name=$(basename "$gcc_path")
    prefix=${gcc_name%-gcc}
    # Full path prefix so we don't need to modify PATH
    cross_compile="$tc_dir/bin/$prefix-"
    sysroot=$("$gcc_path" -print-sysroot)
    extra_cflags="--sysroot=$sysroot"
    extra_ldflags="--sysroot=$sysroot"
    install_dir="$INSTALL_BASE/$out_arch"
    static_binary="$OUTPUT_DIR/busybox-static-$out_arch"

    echo ""
    echo "=== Building busybox for $out_arch ($arch_key) ==="
    echo "Toolchain dir: $tc_dir"
    echo "CC: $gcc_path"
    echo "Sysroot: $sysroot"
    echo "CROSS_COMPILE prefix: $cross_compile"
    echo "EXTRA_CFLAGS: $extra_cflags"
    echo "EXTRA_LDFLAGS: $extra_ldflags"

    (
        cd "$SRC_DIR"
        trap 'make distclean >/dev/null 2>&1 || true' EXIT
        make distclean >/dev/null 2>&1 || true
        make defconfig >/dev/null 2>&1

        # Set full-path cross compiler prefix in .config so ar/ld/strip etc
        # all come from the toolchain, not the host.
        set_config CONFIG_CROSS_COMPILER_PREFIX "\"$cross_compile\""
        set_config CONFIG_STATIC y

        make silentoldconfig >/dev/null 2>&1

        make \
            EXTRA_CFLAGS="$extra_cflags" \
            EXTRA_LDFLAGS="$extra_ldflags" \
            -j"$(nproc)"

        # Strip binary (cross strip is used automatically via CROSS_COMPILE)
        if [ -x "$cross_compile"strip ]; then
            "$cross_compile"strip busybox
        fi

        # Install to busybox_install/{arch}
        rm -rf "../$install_dir"
        mkdir -p "../$install_dir"
        make \
            EXTRA_CFLAGS="$extra_cflags" \
            EXTRA_LDFLAGS="$extra_ldflags" \
            CONFIG_PREFIX="../$install_dir" \
            install >/dev/null 2>&1

        # Copy static binary to busybox_static/
        cp busybox "../$static_binary"
    )
    echo "=== Finished $out_arch: $static_binary ==="
done

echo ""
echo "=== All builds finished ==="
