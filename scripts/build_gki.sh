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
# LOCALVERSION must be *set* (even to empty) so scripts/setlocalversion does not
# append "+"/"-g<hash>" to the pinned stock localversion.
export LOCALVERSION=""

CC="clang"
if command -v ccache >/dev/null 2>&1; then
  CC="ccache clang"
fi

echo "=== GKI build: JOBS=$JOBS (nproc=$(nproc)), CC=$CC ==="
OUT=out-gki
rm -rf "$OUT"; mkdir -p "$OUT"

make O="$OUT" ARCH=arm64 LLVM=1 CC="$CC" gki_defconfig 2>&1 | tee gki-config.log

# Keep the compiled kernel release identical to the stock device kernel:
#   stock: 6.6.118-android15-8-g0908354dac1b-ab16143355-4k
if [ -n "${KERNEL_LOCALVERSION:-}" ]; then
  ./scripts/config --file "$OUT/.config" \
    --set-str LOCALVERSION "$KERNEL_LOCALVERSION" \
    --disable LOCALVERSION_AUTO
  make O="$OUT" ARCH=arm64 LLVM=1 CC="$CC" olddefconfig 2>&1 | tee -a gki-config.log
fi

REL=$(make -s O="$OUT" ARCH=arm64 LLVM=1 CC="$CC" kernelrelease 2>/dev/null | tail -n 1 || true)
echo "kernelrelease: ${REL}"

grep -E '^CONFIG_(LOCALVERSION|ARM64_4K_PAGES|MODVERSIONS|KASAN|LOCKDEP)=' "$OUT/.config" || true

make O="$OUT" ARCH=arm64 LLVM=1 CC="$CC" -j"$JOBS" Image 2>&1 | tee gki-build.log

strings "$OUT/arch/arm64/boot/Image" | grep -m1 'Linux version' | tee -a gki-build.log || true
strings "$OUT/arch/arm64/boot/Image" | grep -m1 'vermagic=' | tee -a gki-build.log || true

printf 'PLAIN_OUT=%s\nPLAIN_IMAGE=%s/arch/arm64/boot/Image\n' "$OUT" "$OUT" > plain-build.txt
echo "BUILD_OK variant=gki"
