#!/usr/bin/env bash
# Build the ACK (AOSP common) GKI kernel matching the device's stock branch.
# Usage: build_gki.sh <kernel-source-dir>
set -euo pipefail

SRC="${1:?kernel source dir required}"
cd "$SRC"

export ARCH=arm64
export LLVM=1
JOBS="${JOBS:-}"
if [ -z "$JOBS" ] || [ "$JOBS" = "0" ]; then
  JOBS="$(nproc)"
fi
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-6G}"
export CCACHE_COMPRESS="${CCACHE_COMPRESS:-1}"

CC="clang"
if command -v ccache >/dev/null 2>&1; then
  CC="ccache clang"
fi

echo "=== GKI build: JOBS=$JOBS (nproc=$(nproc)), CC=$CC ==="
OUT=out-gki
rm -rf "$OUT"; mkdir -p "$OUT"

make O="$OUT" ARCH=arm64 LLVM=1 CC="$CC" gki_defconfig 2>&1 | tee gki-config.log
grep -E '^CONFIG_(LOCALVERSION|ARM64_4K_PAGES|MODVERSIONS|KASAN|LOCKDEP)=' "$OUT/.config" || true

make O="$OUT" ARCH=arm64 LLVM=1 CC="$CC" -j"$JOBS" Image 2>&1 | tee gki-build.log

printf 'PLAIN_OUT=%s\nPLAIN_IMAGE=%s/arch/arm64/boot/Image\n' "$OUT" "$OUT" > plain-build.txt
echo "BUILD_OK variant=gki"
