#!/usr/bin/env bash
#
# merge_files.sh
#
# Copy our `files/` overlay into the current OpenWrt build tree. Designed
# for the modern firewall4/nftables-based OpenWrt 24.10 / 25.12 lineage:
# we no longer inject iptables rules into files/etc/firewall.user.

set -u

log()  { echo "[merge_files] $*"; }
warn() { echo "[merge_files][WARN] $*" >&2; }

WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"

# CWD should be the OpenWrt source root.
if [ ! -d package ] || [ ! -d target ]; then
    warn "CWD does not look like an OpenWrt tree; skipping file overlay."
    return 0 2>/dev/null || exit 0
fi

SRC_FILES="$WORKSPACE/files"
if [ ! -d "$SRC_FILES" ]; then
    log "no files/ overlay in repo, nothing to merge"
    return 0 2>/dev/null || exit 0
fi

mkdir -p files
cp -a "$SRC_FILES/." files/

# Tighten dropbear key permissions if any shipped.
if [ -d files/etc/dropbear ]; then
    chmod 600 files/etc/dropbear/* 2>/dev/null || true
fi

log "overlay merged from $SRC_FILES"
