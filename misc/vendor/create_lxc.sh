#!/usr/bin/env bash
set -euo pipefail

: "${CTID:?CTID is required}"
: "${PCT_OSTYPE:?PCT_OSTYPE is required}"
: "${PCT_OSVERSION:?PCT_OSVERSION is required}"
: "${PCT_OPTIONS:?PCT_OPTIONS is required}"
: "${PCT_DISK_SIZE:?PCT_DISK_SIZE is required}"

if (( CTID < 100 )); then
  exit 205
fi

if pct status "$CTID" >/dev/null 2>&1; then
  exit 206
fi

STORAGE_POOL="${STORAGE_POOL:-}"
if [[ -z "$STORAGE_POOL" ]]; then
  STORAGE_POOL=$(pvesm status -content rootdir | awk 'NR==2{print $1}')
fi
if [[ -z "$STORAGE_POOL" ]]; then
  exit 201
fi

TEMPLATE_SECTION="${TEMPLATE_SECTION:-system}"
TEMPLATE=$(pveam available --section "$TEMPLATE_SECTION" | awk '{print $2}' | grep -m1 "^${PCT_OSTYPE}-${PCT_OSVERSION}" || true)
if [[ -z "$TEMPLATE" ]]; then
  exit 207
fi

if ! pveam list local | awk '{print $2}' | grep -q "$TEMPLATE"; then
  if ! pveam download local "$TEMPLATE"; then
    exit 208
  fi
fi

ROOTFS_SPEC="${STORAGE_POOL}:${PCT_DISK_SIZE}"

if ! pct create "$CTID" "local:vztmpl/${TEMPLATE}" -rootfs "$ROOTFS_SPEC" $PCT_OPTIONS; then
  exit 200
fi

pct start "$CTID" || exit 200
