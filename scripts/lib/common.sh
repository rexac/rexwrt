#!/usr/bin/env bash
# Shared build context. Source this from scripts; executable entry is ./rexwrt.
REXWRT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export REXWRT_ROOT

die() { printf 'rexwrt: %s\n' "$*" >&2; exit 1; }
log() { printf '\n[rexwrt] %s\n' "$*"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
seed_config() {
  # Device settings override shared defaults without duplicate Kconfig symbols.
  awk '
    { lines[NR]=$0; key="" }
    /^CONFIG_[[:alnum:]_-]+=/ { key=$0; sub(/=.*/, "", key) }
    /^# CONFIG_[[:alnum:]_-]+ is not set$/ { key=$2 }
    { if (key != "") { symbols[NR]=key; last[key]=NR } }
    END { for (i=1; i<=NR; i++) if (!(i in symbols) || last[symbols[i]]==i) print lines[i] }
  ' "$REXWRT_ROOT/config/common.seed" "$DEVICE_DIR/config.seed"
}
list_devices() {
  local config
  for config in "$REXWRT_ROOT"/devices/*/config.seed; do
    basename "$(dirname "$config")"
  done
}
load_device() {
  [[ "$DEVICE" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Invalid device: $DEVICE"
  DEVICE_DIR=$REXWRT_ROOT/devices/$DEVICE
  [[ -f "$DEVICE_DIR/config.seed" ]] || die "Unknown device: $DEVICE (see ./rexwrt devices)"
  TARGET_BOARD=$(sed -n 's/^CONFIG_TARGET_\([a-z0-9]*\)=y$/\1/p' "$DEVICE_DIR/config.seed")
  TARGET_SUBTARGET=$(sed -n "s/^CONFIG_TARGET_${TARGET_BOARD}_\([a-z0-9]*\)=y$/\1/p" "$DEVICE_DIR/config.seed")
  [[ -n "$TARGET_BOARD" && -n "$TARGET_SUBTARGET" ]] || die "Invalid target in $DEVICE_DIR/config.seed"
  export DEVICE DEVICE_DIR TARGET_BOARD TARGET_SUBTARGET
}
