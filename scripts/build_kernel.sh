#!/usr/bin/env bash
# Build annibale vmlinux (Image) with the correct QCOM defconfig merge:
#   gki_defconfig + sun/annibale perf fragments (+ consolidate fragments).
# Usage: build_kernel.sh <kernel-source-dir>
set -euo pipefail

SRC="${1:?kernel source dir required}"
cd "$SRC"

export ARCH=arm64
export LLVM=1
JOBS="${JOBS:-}"
if [ -z "$JOBS" ] || [ "$JOBS" = "0" ]; then
  JOBS="$(nproc)"
fi
export JOBS
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-6G}"
export CCACHE_COMPRESS="${CCACHE_COMPRESS:-1}"

CC="clang"
if command -v ccache >/dev/null 2>&1; then
  CC="ccache clang"
fi

echo "=== build parallelism: JOBS=$JOBS (nproc=$(nproc)), CC=$CC ==="

base_fragments() {
  echo "arch/arm64/configs/gki_defconfig"
  echo "arch/arm64/configs/vendor/sun_perf.config"
  echo "arch/arm64/configs/vendor/annibale_perf.config"
}

consolidate_fragments() {
  base_fragments
  [ -f arch/arm64/configs/consolidate.fragment ] && echo "arch/arm64/configs/consolidate.fragment"
  for f in arch/arm64/configs/vendor/sun_consolidate.config \
           arch/arm64/configs/vendor/annibale_consolidate.config; do
    [ -f "$f" ] && echo "$f"
  done
  true
}

build_variant() {
  local variant="$1"; shift
  local frags=("$@")
  local out="out-$variant"
  local mlog="merge-$variant.log"
  local blog="build-$variant.log"

  echo "=========== variant: $variant ==========="
  echo "fragments: ${frags[*]}"
  rm -rf "$out"; mkdir -p "$out"

  KCONFIG_CONFIG="$out/.config" scripts/kconfig/merge_config.sh -m -r -y "${frags[@]}" 2>&1 | tee "$mlog"
  if ! make O="$out" ARCH=arm64 LLVM=1 CC="$CC" olddefconfig 2>&1 | tee -a "$blog"; then
    echo "olddefconfig failed for $variant"
    return 1
  fi
  grep -E '^CONFIG_REGMAP=' "$out/.config" || true
  grep -E '^CONFIG_MI_WIFI_GPIO=' "$out/.config" || true
  if make O="$out" ARCH=arm64 LLVM=1 CC="$CC" -j"$JOBS" Image 2>&1 | tee -a "$blog"; then
    printf 'PLAIN_OUT=%s\nPLAIN_IMAGE=%s/arch/arm64/boot/Image\n' "$out" "$out" > plain-build.txt
    echo "BUILD_OK variant=$variant"
    return 0
  fi
  echo "Image build failed for $variant"
  return 1
}

# Production variant (perf) first; consolidate is a debug config (KASAN/LOCKDEP).
mapfile -t PERF < <(base_fragments)
if build_variant perf "${PERF[@]}"; then
  exit 0
fi

mapfile -t CONS < <(consolidate_fragments)
if build_variant consolidate "${CONS[@]}"; then
  exit 0
fi

echo "::error::all defconfig variants failed"
exit 1
