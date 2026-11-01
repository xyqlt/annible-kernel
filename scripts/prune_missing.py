#!/usr/bin/env python3
"""Prune references to directories/Kconfig files that Xiaomi did not publish.

The Xiaomi OSS snapshot references some vendor directories that are not part of
the open-source drop (e.g. drivers/misc/hwid/Kconfig). This script comments
those references out so Kconfig parsing and kbuild can proceed.

Usage: prune_missing.py <kernel-tree>
"""
import os
import re
import sys

SRC = os.path.abspath(sys.argv[1])
os.chdir(SRC)

EXCLUDE_DIRS = {".git", "out"}
kconfig_src = re.compile(r'^(\s*)source\s+"([^"]+)"\s*$')
make_assign = re.compile(r'^(\s*)([A-Za-z0-9_$().+-]+)\s*[:+]?=\s*(.*)$')


def walk_files():
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS and not d.startswith("out-")]
        for f in files:
            yield os.path.normpath(os.path.join(root, f))


def prune_kconfig(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return 0
    changed = 0
    for i, line in enumerate(lines):
        m = kconfig_src.match(line)
        if not m:
            continue
        target = m.group(2)
        if "$" in target:
            continue
        if not os.path.exists(target):
            lines[i] = m.group(1) + "# [pruned-missing] " + line.strip() + "\n"
            changed += 1
    if changed:
        with open(path, "w", encoding="utf-8", errors="replace") as fh:
            fh.writelines(lines)
    return changed


def prune_makefile(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return 0
    changed = 0
    here = os.path.dirname(path)
    for i, line in enumerate(lines):
        m = make_assign.match(line)
        if not m:
            continue
        lhs, rhs = m.group(2), m.group(3)
        if not (lhs.startswith("obj-") or lhs.startswith("subdir-")
                or lhs.startswith("always-") or lhs.startswith("extra-")):
            continue
        tokens = rhs.split()
        if not tokens:
            continue
        kept, dropped = [], []
        for tok in tokens:
            # Makefile subdirs are relative to the Makefile's own directory,
            # NOT to the kernel tree root.
            if (tok.endswith("/") and "$" not in tok and "*" not in tok
                    and not os.path.exists(os.path.join(here, tok.rstrip("/")))):
                dropped.append(tok)
            else:
                kept.append(tok)
        if not dropped:
            continue
        changed += len(dropped)
        eq = line.find("=")
        if kept:
            lines[i] = line[: eq + 1] + " " + " ".join(kept) + "\n"
        else:
            lines[i] = f"# [pruned-missing] {line.strip()}\n"
    if changed:
        with open(path, "w", encoding="utf-8", errors="replace") as fh:
            fh.writelines(lines)
    return changed


def main():
    k = 0
    m = 0
    for path in walk_files():
        base = os.path.basename(path)
        if base.startswith("Kconfig"):
            k += prune_kconfig(path)
        elif base in ("Makefile", "Kbuild"):
            m += prune_makefile(path)
    print(f"pruned: {k} Kconfig source lines, {m} Makefile directory tokens")


if __name__ == "__main__":
    main()
