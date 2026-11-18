#!/usr/bin/env bash
# Adapt FriendlyElec's SDIO driver to OpenWrt's separate cfg80211 backport.
set -euo pipefail
root=${1:?FriendlyElec source directory required}
kernel=${2:?Target kernel source required}
cfg80211=${3:?Staged cfg80211 header required}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
driver=$root
[[ -f "$driver/aic8800_fdrv/rwnx_main.c" && -d "$root/fw/aic8800D80" ]] || {
  echo 'Unrecognized FriendlyElec AIC8800 SDIO source layout' >&2; exit 1;
}
# Read the APIs actually supplied by OpenWrt rather than assuming that its
# wireless backport and core kernel have the same version or vendor changes.
for header in "$cfg80211" "$kernel/include/linux/timer.h" "$kernel/include/linux/module.h"; do
  [[ -s "$header" ]] || { printf 'Missing driver compatibility header: %s\n' "$header" >&2; exit 1; }
done
callback() {
  awk -v name="$1" '
    index($0, "(*" name ")") {active=1}
    active {print; if ($0 ~ /;/) exit}
  ' "$cfg80211"
}
tx=$(callback set_tx_power)
wiphy=$(callback set_wiphy_params)
monitor=$(callback set_monitor_channel)
[[ -n "$tx" && -n "$wiphy" && -n "$monitor" ]] || { echo 'Unrecognized cfg80211 callbacks' >&2; exit 1; }
tx_radio=0 wiphy_radio=0 monitor_dev=0 timer_api=0 namespace_strings=0
[[ "$tx" != *radio_idx* ]] || tx_radio=1
[[ "$wiphy" != *radio_idx* ]] || wiphy_radio=1
[[ "$monitor" != *'struct net_device'* ]] || monitor_dev=1
if ! grep -Eq '(^|[^[:alnum:]_])del_timer_sync[[:space:]]*\(' "$kernel/include/linux/timer.h"; then
  grep -Eq '(^|[^[:alnum:]_])timer_delete_sync[[:space:]]*\(' "$kernel/include/linux/timer.h" || { echo 'Unrecognized timer API' >&2; exit 1; }
  timer_api=1
fi
if grep -Eq '^#define MODULE_IMPORT_NS\(ns\).*import_ns,[[:space:]]*ns\)' "$kernel/include/linux/module.h"; then namespace_strings=1; fi
while IFS= read -r file; do
  awk -v tx_radio="$tx_radio" -v wiphy_radio="$wiphy_radio" -v monitor_dev="$monitor_dev" \
    -v timer_api="$timer_api" -v namespace_strings="$namespace_strings" \
    -f "$script_dir/wireless-guards.awk" "$file" > "$file.rexwrt"
  mv "$file.rexwrt" "$file"
done < <(find "$driver/aic8800_bsp" "$driver/aic8800_fdrv" -type f \( -name '*.c' -o -name '*.h' \))
