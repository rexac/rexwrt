#!/usr/bin/env bash
# Apply Radxa's maintained patch series before adapting cfg80211 version guards.
set -euo pipefail
root=${1:?Radxa source directory required}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ -f "$root/debian/patches/series" ]] || { echo 'Missing Radxa compatibility patch series' >&2; exit 1; }
while read -r patch options; do
  [[ -n "$patch" && "$patch" != \#* ]] || continue
  [[ "$patch" =~ ^[a-zA-Z0-9._-]+$ && -z "${options:-}" ]] || { echo 'Unsupported Radxa patch series format' >&2; exit 1; }
  # USB and PCIe changes are unrelated to this package; preserve series order.
  git -C "$root" apply --whitespace=nowarn --include='src/SDIO/*' "$root/debian/patches/$patch"
done < "$root/debian/patches/series"
driver=$root/src/SDIO/driver_fw/driver/aic8800
[[ -f "$driver/aic8800_fdrv/rwnx_main.c" && -d "$root/src/SDIO/driver_fw/fw/aic8800D80" ]]
while IFS= read -r file; do
  awk -f "$script_dir/wireless-guards.awk" "$file" > "$file.rexwrt"
  mv "$file.rexwrt" "$file"
done < <(find "$driver" -type f \( -name '*.c' -o -name '*.h' \))
