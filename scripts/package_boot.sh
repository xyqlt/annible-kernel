#!/usr/bin/env bash
# Build boot.img (header v4 + AVB hash footer) for annibale.
# Usage: package_boot.sh <Image> <out_dir> [partition_size]
set -euo pipefail

IMG="${1:?Image required}"
OUT="${2:?out dir required}"
PART_SIZE="${3:-100663296}"   # 96 MiB: stock annibale boot partition size

mkdir -p "$OUT"
cp -f "$IMG" "$OUT/Image"

WORK=$(mktemp -d)
git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg "$WORK/mkbootimg"
git clone --depth=1 https://android.googlesource.com/platform/external/avb "$WORK/avb"
chmod +x "$WORK/avb/avbtool" 2>/dev/null || true

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$WORK/key.pem" 2>/dev/null

python3 "$WORK/mkbootimg/mkbootimg.py" \
  --header_version 4 \
  --kernel "$OUT/Image" \
  --output "$OUT/boot.img"

python3 "$WORK/avb/avbtool" add_hash_footer \
  --partition_name boot \
  --partition_size "$PART_SIZE" \
  --image "$OUT/boot.img" \
  --algorithm SHA256_RSA2048 \
  --key "$WORK/key.pem"

ls -l "$OUT"
python3 - "$OUT/boot.img" <<'PY'
import struct, sys
p = sys.argv[1]
b = open(p, 'rb').read()
assert b[:8] == b'ANDROID!', 'not a boot image'
kernel_size, ramdisk_size = struct.unpack_from('<II', b, 8)
header_version = struct.unpack_from('<I', b, 40)[0]
print(f'boot.img: size={len(b)} header_version={header_version} kernel={kernel_size} ramdisk={ramdisk_size}')
PY
