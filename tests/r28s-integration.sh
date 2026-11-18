#!/usr/bin/env bash
# Replay the complete adapter against real stable and snapshot source archives.
# Usage: r28s-integration.sh STABLE_TAR SNAPSHOT_TAR SOURCE_BUNDLE KERNEL_CACHE
set -euo pipefail
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ $# == 4 ]] || { echo 'Usage: r28s-integration.sh STABLE_TAR SNAPSHOT_TAR SOURCE_BUNDLE KERNEL_CACHE' >&2; exit 1; }
absolute() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$PWD" "$(basename "$1")"); }
stable=$(absolute "$1")
snapshot=$(absolute "$2")
export REXWRT_R28S_SOURCES=$(absolute "$3") REXWRT_UPSTREAM_CACHE=$(absolute "$4")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
manifest() { (cd "$1" && find . -type f -exec shasum -a 256 {} + | LC_ALL=C sort); }
mkdir -p "$work/bin"
printf '#!/bin/sh\necho "Unexpected network access during replay" >&2\nexit 1\n' > "$work/bin/curl"
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH"
for channel in stable snapshot; do
  archive=$stable
  [[ "$channel" != snapshot ]] || archive=$snapshot
  prefix=$(tar -tzf "$archive" | head -1 | cut -d/ -f1) || [[ -n "${prefix:-}" ]]
  tree=$work/$channel
  mkdir -p "$tree"
  tar -xzf "$archive" -C "$tree" --strip-components=1 \
    "$prefix/target/linux/rockchip" "$prefix/target/linux/generic" "$prefix/include" \
    "$prefix/package/boot/uboot-rockchip" "$prefix/package/kernel/mac80211/Makefile"
  manifest "$tree" > "$work/before"
  manifest "$tree/package/boot/uboot-rockchip" > "$work/boot-before"
  "$project/rexwrt" adapt --device nanopi-r28s --source "$tree" --dry-run
  manifest "$tree" > "$work/after"
  cmp "$work/before" "$work/after"
  "$project/rexwrt" adapt --device nanopi-r28s --source "$tree"
  manifest "$tree/package/boot/uboot-rockchip" > "$work/boot-after"
  cmp "$work/boot-before" "$work/boot-after"
  kernel=$(sed -n 's/^KERNEL_PATCHVER:=//p' "$tree/target/linux/rockchip/Makefile")
  [[ -s "$tree/target/linux/rockchip/patches-$kernel/999-rexwrt-r28s.patch" ]]
  [[ -s "$tree/.rexwrt/r28s/sources.json" ]]
  manifest "$tree" > "$work/before"
  "$project/rexwrt" adapt --device nanopi-r28s --source "$tree"
  manifest "$tree" > "$work/after"
  cmp "$work/before" "$work/after"
  printf 'PASS: %s dynamic adaptation (Linux %s), dry run, boot isolation and idempotence\n' "$channel" "$kernel"
done
