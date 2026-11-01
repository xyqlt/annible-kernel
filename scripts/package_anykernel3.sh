#!/usr/bin/env bash
# Build a kernel-only AnyKernel3 flashable zip (no boot.img/AVB handling).
# Usage: package_anykernel3.sh <Image> <out_dir> [zip_name]
set -euo pipefail

IMG="${1:?Image required}"
OUT="${2:?out dir required}"
NAME="${3:-AnyKernel3.zip}"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)"

echo "=== cloning AnyKernel3 template (WildKernels gki-2.0) ==="
git clone --depth=1 --branch gki-2.0 https://github.com/WildKernels/AnyKernel3.git "$WORK/ak3"
rm -rf "$WORK/ak3/.git"

[ -f "$WORK/ak3/anykernel.sh" ] || { echo "::error::anykernel.sh missing in template"; exit 1; }
cp "$IMG" "$WORK/ak3/Image"

grep -E 'do\.devicecheck|block=|kernel\.string' "$WORK/ak3/anykernel.sh" || true

( cd "$WORK/ak3" && zip -r -9 "$OUT/$NAME" . >/dev/null )

ls -l "$OUT/$NAME"
sha256sum "$OUT/$NAME" || true
echo "AK3 created: $OUT/$NAME"
