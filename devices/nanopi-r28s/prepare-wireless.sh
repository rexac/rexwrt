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
# The command allocator is shared across translation units. Declare its public
# functions in their shared header instead of disabling missing-prototype errors.
header=$driver/aic8800_fdrv/rwnx_cmds.h
awk '
  BEGIN {
    names[1]="rwnx_cmd_malloc"; declarations[1]="struct rwnx_cmd *rwnx_cmd_malloc(void);"
    names[2]="rwnx_cmd_free"; declarations[2]="void rwnx_cmd_free(struct rwnx_cmd *cmd);"
    names[3]="rwnx_init_cmd_array"; declarations[3]="int rwnx_init_cmd_array(void);"
    names[4]="rwnx_free_cmd_array"; declarations[4]="void rwnx_free_cmd_array(void);"
  }
  {
    lines[NR]=$0
    for (j=1; j<=4; j++)
      if ($0 ~ ("(^|[^[:alnum:]_])" names[j] "[[:space:]]*\\(.*\\)[[:space:]]*;")) present[j]=1
  }
  END {
    for (i=1; i<=NR; i++) {
      print lines[i]
      if (lines[i] ~ /^#define[[:space:]]+_RWNX_CMDS_H_[[:space:]]*$/) {
        guards++
        missing=0
        for (j=1; j<=4; j++) if (!present[j]) missing++
        if (missing) {
          print "\n/* Shared command allocation and lifecycle API. */"
          print "struct rwnx_cmd;"
          for (j=1; j<=4; j++) if (!present[j]) print declarations[j]
        }
      }
    }
    if (guards!=1) exit 1
  }
' "$header" > "$header.rexwrt" || { rm -f "$header.rexwrt"; echo 'Unrecognized AIC8800 command header' >&2; exit 1; }
mv "$header.rexwrt" "$header"
while IFS= read -r file; do
  awk -f "$script_dir/wireless-guards.awk" "$file" > "$file.rexwrt"
  mv "$file.rexwrt" "$file"
done < <(find "$driver" -type f \( -name '*.c' -o -name '*.h' \))
