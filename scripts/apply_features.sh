#!/usr/bin/env bash
# Apply annibale kernel features on top of the Xiaomi source tree.
# Usage: apply_features.sh <kernel-source-dir>
# Env: MODE(baseline|bakasu|full), ENABLE_BBG/DROIDSPACES/NTSYNC/NOMOUNT/ZRAM/NETWORK=0|1
set -euo pipefail

SRC="${1:?kernel source dir required}"
MODE="${MODE:-baseline}"
ENABLE_BBG="${ENABLE_BBG:-0}"
ENABLE_DROIDSPACES="${ENABLE_DROIDSPACES:-0}"
ENABLE_NTSYNC="${ENABLE_NTSYNC:-0}"
ENABLE_NOMOUNT="${ENABLE_NOMOUNT:-0}"
ENABLE_ZRAM="${ENABLE_ZRAM:-0}"
ENABLE_NETWORK="${ENABLE_NETWORK:-0}"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '::warning::%s\n' "$*"; }

cd "$SRC"

# ---------------------------------------------------------------- config files
CONFIGS=$(find . -maxdepth 5 -type f \( -name 'annibale_consolidate.config' -o -name 'annibale_perf.config' \) | sort)
if [ -z "$CONFIGS" ]; then
  CONFIGS=$(find . -maxdepth 5 -type f -name '*annibale*.config' | sort)
fi
if [ -z "$CONFIGS" ]; then
  echo "::error::annibale defconfig not found"
  exit 1
fi
log "config files:"; echo "$CONFIGS"

add_cfg() { # add_cfg NAME=VALUE
  local line="$1" f
  for f in $CONFIGS; do
    grep -qxF "$line" "$f" 2>/dev/null || printf '%s\n' "$line" >> "$f"
  done
}

# ---------------------------------------------------------------- BakaSU
if [ "$MODE" != "baseline" ]; then
  log "installing BakaSU (built-in KernelSU + SUSFS)"
  curl -LSs https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh -o /tmp/bakasu-setup.sh
  bash /tmp/bakasu-setup.sh -s main
  add_cfg 'CONFIG_KSU=y'
  add_cfg 'CONFIG_KSU_SUSFS=y'
  add_cfg 'CONFIG_KSU_SUSFS_SUS_PATH=y'
  add_cfg 'CONFIG_KSU_SUSFS_SUS_MOUNT=y'
  add_cfg 'CONFIG_KSU_SUSFS_SUS_KSTAT=y'
  add_cfg 'CONFIG_KSU_SUSFS_SPOOF_UNAME=y'
  add_cfg 'CONFIG_KSU_SUSFS_ENABLE_LOG=y'
  add_cfg 'CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y'
  add_cfg 'CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y'
  add_cfg 'CONFIG_KSU_SUSFS_OPEN_REDIRECT=y'
  add_cfg 'CONFIG_KSU_SUSFS_SUS_MAP=y'
  add_cfg 'CONFIG_TMPFS_XATTR=y'
  add_cfg 'CONFIG_TMPFS_POSIX_ACL=y'
fi

# ---------------------------------------------------------------- remove module-list entries for builtin features
drop_module() { # drop_module path/name.ko
  local mod="$1" f
  for f in annibale.bzl modules.list.*; do
    [ -f "$f" ] && sed -i "\\|${mod}|d" "$f" || true
  done
}

# ---------------------------------------------------------------- NoMount
if [ "$ENABLE_NOMOUNT" = "1" ]; then
  log "integrating NoMount"
  curl -fsSL --retry 5 --retry-all-errors \
    https://raw.githubusercontent.com/maxsteeel/nomount/refs/heads/dev/kernel/setup.sh | bash -s dev
  [ -L fs/nomount ] || warn "fs/nomount symlink missing, NoMount may have failed"
  add_cfg 'CONFIG_NOMOUNT=y'
fi

# ---------------------------------------------------------------- BBG
if [ "$ENABLE_BBG" = "1" ]; then
  log "integrating Baseband-guard (BBG)"
  wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash
  add_cfg 'CONFIG_BBG=y'
fi

# ---------------------------------------------------------------- Droidspaces (SYSVIPC kABI)
if [ "$ENABLE_DROIDSPACES" = "1" ]; then
  log "integrating Droidspaces kernel patches (6.6, kABI slot 6_7_8)"
  rm -rf /tmp/Droidspaces-OSS
  git clone --depth 1 https://github.com/ravindu644/Droidspaces-OSS.git /tmp/Droidspaces-OSS
  PATCH_DIR=/tmp/Droidspaces-OSS/Documentation/resources/kernel-patches/GKI/below-kernel-6.12
  if patch -p1 --dry-run < "$PATCH_DIR/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch" >/dev/null 2>&1; then
    patch -p1 --forward < "$PATCH_DIR/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch"
  else
    warn "SYSVIPC kABI patch does not apply cleanly to 6.6.57; continuing WITHOUT SYSVIPC"
    ENABLE_DROIDSPACES=0
  fi
  if [ "$ENABLE_DROIDSPACES" = "1" ]; then
    add_cfg 'CONFIG_SYSVIPC=y'
    add_cfg 'CONFIG_POSIX_MQUEUE=y'
    add_cfg 'CONFIG_IPC_NS=y'
    add_cfg 'CONFIG_PID_NS=y'
    add_cfg 'CONFIG_USER_NS=y'
    add_cfg 'CONFIG_DEVTMPFS=y'
    add_cfg 'CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y'
    add_cfg 'CONFIG_NETFILTER_XT_TARGET_LOG=y'
    add_cfg 'CONFIG_NETFILTER_XT_MATCH_RECENT=y'
    add_cfg 'CONFIG_IP_SET=y'
    add_cfg 'CONFIG_IP_SET_HASH_IP=y'
    add_cfg 'CONFIG_IP_SET_HASH_NET=y'
    add_cfg 'CONFIG_NETFILTER_XT_SET=y'
    add_cfg 'CONFIG_IP_SET_MAX=65534'
  fi
fi

# ---------------------------------------------------------------- NTSync
if [ "$ENABLE_NTSYNC" = "1" ]; then
  log "enabling NTSync"
  if grep -RqsE '^[[:space:]]*config[[:space:]]+NTSYNC' drivers/misc 2>/dev/null; then
    add_cfg 'CONFIG_NTSYNC=y'
    drop_module 'drivers/misc/ntsync.ko'
  else
    warn "NTSync Kconfig not found in tree; skipped (needs backport patch)"
  fi
fi

# ---------------------------------------------------------------- ZRAM
if [ "$ENABLE_ZRAM" = "1" ]; then
  log "enabling ZRAM (builtin, lz4hc, multi-comp)"
  add_cfg 'CONFIG_ZRAM=y'
  add_cfg 'CONFIG_ZSMALLOC=y'
  add_cfg 'CONFIG_ZRAM_MULTI_COMP=y'
  add_cfg 'CONFIG_ZRAM_WRITEBACK=y'
  add_cfg 'CONFIG_CRYPTO_LZ4=y'
  add_cfg 'CONFIG_CRYPTO_LZ4HC=y'
  add_cfg 'CONFIG_LZ4_COMPRESS=y'
  add_cfg 'CONFIG_LZ4HC_COMPRESS=y'
  add_cfg 'CONFIG_LZ4_DECOMPRESS=y'
  add_cfg 'CONFIG_CRYPTO_LZ4K=y'
  add_cfg 'CONFIG_CRYPTO_LZ4KD=y'
  drop_module 'drivers/block/zram/zram.ko'
  drop_module 'mm/zsmalloc.ko'
fi

# ---------------------------------------------------------------- Network
if [ "$ENABLE_NETWORK" = "1" ]; then
  log "network enhancements (BBRv3 + IPSet + CAKE + CIFS/TTL)"
  rm -rf /tmp/kernel_patches
  git clone --depth 1 https://github.com/WildKernels/kernel_patches.git /tmp/kernel_patches || true
  BBR3=/tmp/kernel_patches/common/bbrv3/0001-net-tcp-backport-BBRv3-to-android15-6.6.patch
  if [ -f "$BBR3" ]; then
    if patch -p1 --dry-run < "$BBR3" >/dev/null 2>&1; then
      patch -p1 --no-backup-if-mismatch < "$BBR3"
      add_cfg 'CONFIG_TCP_CONG_BBR3=y'
      add_cfg 'CONFIG_DEFAULT_BBR3=y'
      add_cfg 'CONFIG_DEFAULT_TCP_CONG="bbr3"'
    else
      warn "BBRv3 patch does not apply to this tree; keep default congestion control"
    fi
  else
    warn "BBRv3 patch not found; skipped"
  fi

  for c in TCP_CONG_BBR TCP_CONG_CUBIC TCP_CONG_BIC TCP_CONG_WESTWOOD TCP_CONG_HTCP \
           NET_SCH_FQ NET_SCH_FQ_CODEL NET_SCH_CAKE NET_ACT_CONNMARK NET_CLS_ACT \
           IP_NF_TARGET_TTL IP6_NF_TARGET_HL IP6_NF_MATCH_HL \
           IP_SET IP_SET_HASH_IP IP_SET_HASH_NET NETFILTER_XT_SET \
           NETFILTER_XT_MATCH_ADDRTYPE NETFILTER_XT_TARGET_LOG NETFILTER_XT_MATCH_RECENT \
           IP6_NF_NAT IP6_NF_TARGET_MASQUERADE \
           CIFS NETWORK_FILESYSTEMS KEYS CIFS_XATTR CIFS_POSIX; do
    add_cfg "CONFIG_${c}=y"
  done
fi

log "feature application done (mode=$MODE)"
git status --short | head -50 || true
