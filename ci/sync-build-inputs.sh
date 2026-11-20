#!/usr/bin/env bash
# Generate native Actions choices from local devices and official release tags.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workflow=${1:-$root/.github/workflows/build.yml}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"$root/rexwrt" devices > "$work/devices"
[[ -s "$work/devices" ]]
git ls-remote --tags --refs https://github.com/openwrt/openwrt.git > "$work/refs"
awk '{sub(/^refs\/tags\//, "", $2); print $2}' "$work/refs" |
  jq -Rsc 'split("\n") | map(select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))) |
    unique | sort_by(ltrimstr("v") | split(".") | map(tonumber)) | reverse | .[:5]' > "$work/tags"
jq -e 'length > 0' "$work/tags" >/dev/null
{
  printf '      device:\n        description: Device\n        type: choice\n        options:\n'
  while IFS= read -r device; do
    [[ "$device" =~ ^[a-z0-9][a-z0-9-]*$ ]]
    printf '          - %s\n' "$device"
  done < "$work/devices"
  printf '        default: %s\n        required: true\n' "$(head -1 "$work/devices")"
  printf '      branch:\n        description: OpenWrt branch or stable tag\n        type: choice\n        options:\n          - main\n'
  jq -r '.[] | "          - " + .' "$work/tags"
  printf '          - custom\n        default: main\n        required: true\n'
} > "$work/inputs"
awk -v snippet="$work/inputs" '
  /# BEGIN GENERATED BUILD INPUTS$/ {
    begin++; active=1; print
    while ((getline line < snippet)>0) print line
    close(snippet); next
  }
  /# END GENERATED BUILD INPUTS$/ { end++; active=0 }
  !active { print }
  END { if (begin!=1 || end!=1 || active) exit 1 }
' "$workflow" > "$work/workflow"
if ! cmp -s "$work/workflow" "$workflow"; then
  cat "$work/workflow" > "$workflow"
fi
