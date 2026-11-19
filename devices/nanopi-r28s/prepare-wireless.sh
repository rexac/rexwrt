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
# Keep legacy vendor prototype warnings visible within this module tree only.
# Preserve OpenWrt's kernel flags and fatal diagnostics for actual type errors.
[[ -f "$driver/Makefile" ]] || { echo 'Missing AIC8800 module Makefile' >&2; exit 1; }
if ! grep -Fxq 'subdir-ccflags-y += -Wno-error=missing-prototypes' "$driver/Makefile"; then
  printf '\nsubdir-ccflags-y += -Wno-error=missing-prototypes\n' >> "$driver/Makefile"
fi
# The command allocator is shared across translation units. Declare its public
# functions in their shared header even when legacy private helpers only warn.
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
# Initialization is called by rwnx_main.c, so its declaration belongs in the
# shared utility header, not in an extern declaration confined to the caller.
header=$driver/aic8800_fdrv/rwnx_utils.h
awk '
  { lines[NR]=$0; if ($0 ~ /rwnx_init_aic[[:space:]]*\(.*\)[[:space:]]*;/) present=1 }
  END {
    for (i=1; i<=NR; i++) {
      print lines[i]
      if (lines[i] ~ /^struct rwnx_hw;[[:space:]]*$/) {
        anchors++
        if (!present) print "int rwnx_init_aic(struct rwnx_hw *rwnx_hw);"
      }
    }
    if (anchors != 1) exit 1
  }
' "$header" > "$header.rexwrt" || { rm -f "$header.rexwrt"; echo 'Unrecognized AIC8800 utility header' >&2; exit 1; }
mv "$header.rexwrt" "$header"
# This workqueue callback is private to rwnx_cmds.c.
file=$driver/aic8800_fdrv/rwnx_cmds.c
awk '
  /^void cmd_mgr_task_process\(/ { $0="static " $0 }
  { print }
' "$file" > "$file.rexwrt"
mv "$file.rexwrt" "$file"
# The TDLS response intentionally continues into the shared request sender.
# Kernel builds require an attribute rather than a fall-through comment.
file=$driver/aic8800_fdrv/rwnx_main.c
awk '
  /^[[:space:]]*\/\* fall-through \*\/[[:space:]]*$/ {
    sub(/\/\* fall-through \*\//, "fallthrough;")
  }
  { print }
' "$file" > "$file.rexwrt"
mv "$file.rexwrt" "$file"
# Radiotap presence words and payload share the skb allocation. Starting at the
# scalar it_present member incorrectly limits fortified copies to that field.
file=$driver/aic8800_fdrv/rwnx_rx.c
awk '
  /^[[:space:]]*it_present = &rtap->it_present;[[:space:]]*$/ {
    sub(/it_present = &rtap->it_present;/,
        "it_present = (__le32 *)(skb->data + offsetof(struct ieee80211_radiotap_header, it_present));")
  }
  /^[[:space:]]*struct ieee80211_radiotap_he he;[[:space:]]*$/ {
    sub(/he;/, "he = {0};")
  }
  { print }
' "$file" > "$file.rexwrt"
mv "$file.rexwrt" "$file"
while IFS= read -r file; do
  awk -f "$script_dir/wireless-guards.awk" "$file" > "$file.rexwrt"
  mv "$file.rexwrt" "$file"
done < <(find "$driver" -type f \( -name '*.c' -o -name '*.h' \))
