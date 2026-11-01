#!/usr/bin/env bash
# Experimental: merge AOSP ACK security branch into the Xiaomi vendor tree.
# Usage: backport_security.sh <kernel-src> <patchlevel e.g. 2026-10>
# NOTE: requires a non-shallow clone (workflow clones with full history for this mode).
set -euo pipefail

SRC="${1:?src required}"
LEVEL="${2:?patch level required}"
BRANCH="android15-6.6-${LEVEL}"

cd "$SRC"

if [ -f .git/shallow ]; then
  echo "::error::source is a shallow clone; cannot merge unrelated ACK history"
  exit 1
fi

git remote add ack https://android.googlesource.com/kernel/common 2>/dev/null || true
echo "==> fetching ACK $BRANCH"
git fetch ack "$BRANCH"

echo "==> merging ACK $BRANCH"
if git merge --no-edit FETCH_HEAD; then
  echo "merge OK"
else
  echo "::error::merge conflicts; resolve manually (see conflict list below)"
  git diff --name-only --diff-filter=U | head -100 || true
  git merge --abort || true
  exit 1
fi
