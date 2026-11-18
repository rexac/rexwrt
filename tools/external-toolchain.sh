#!/usr/bin/env bash
set -euo pipefail
: "${OPENWRTROOT:?}" "${TARGET_BOARD:?}" "${TARGET_SUBTARGET:?}" "${BRANCH:?}"
case "$BRANCH" in
  main) channel=snapshots ;;
  v[0-9]*.[0-9]*.[0-9]*) channel=releases/${BRANCH#v} ;;
  *) echo 'Prebuilt toolchains require main or a release tag; use --no-prebuilt for other branches.' >&2; exit 1 ;;
esac
url=https://downloads.cdn.openwrt.org/$channel/targets/$TARGET_BOARD/$TARGET_SUBTARGET
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fLSs --retry 3 "$url/sha256sums" -o "$work/sha256sums"
file=$(awk '$2 ~ /^\*?openwrt-toolchain.*\.tar\.(xz|zst|gz)$/ { sub(/^\*/, "", $2); print $2 }' "$work/sha256sums")
[[ -n "$file" && "$file" != *$'\n'* && "$file" != */* ]] || { echo 'Expected one prebuilt toolchain archive' >&2; exit 1; }
curl -fLSs --retry 3 "$url/$file" -o "$work/$file"
(cd "$work" && grep -F "$file" sha256sums | sha256sum --check -)
mkdir -p "$OPENWRTROOT/external-toolchain"
tar -xf "$work/$file" --strip-components=1 -C "$OPENWRTROOT/external-toolchain"
folder=$(find "$OPENWRTROOT/external-toolchain" -maxdepth 1 -type d -name 'toolchain*' -print -quit)
[[ -n "$folder" ]] || { echo 'Toolchain directory missing from archive' >&2; exit 1; }
cd "$OPENWRTROOT"
./scripts/ext-toolchain.sh --toolchain "$folder" --overwrite-config --config "$TARGET_BOARD/$TARGET_SUBTARGET"
