#!/usr/bin/env bash
# Resolve maintained upstream branches and validate the complete port before writing.
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project=$(cd "$script_dir/../.." && pwd)
source "$project/scripts/lib/upstream.sh"
root=${OPENWRTROOT:-}
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --openwrt-root=*) root=${arg#*=} ;;
    --dry-run) dry_run=1 ;;
    *) upstream_die "Unknown argument: $arg" ;;
  esac
done
[[ -n "$root" && -d "$root/target/linux/rockchip" ]] || upstream_die 'Specify an OpenWrt Rockchip tree with --openwrt-root=PATH'
root=$(cd "$root" && pwd)
if [[ -f "$root/.rexwrt/r28s/sources.json" ]]; then
  echo 'R28S adaptation already exists; use a fresh checkout to resolve newer sources.'
  exit 0
fi
for command in curl git jq awk; do command -v "$command" >/dev/null || upstream_die "Missing command: $command"; done
image=target/linux/rockchip/image/armv8.mk
boarddir=target/linux/rockchip/armv8/base-files/etc/board.d
for file in "$image" "$boarddir/01_leds" "$boarddir/02_network" package/kernel/mac80211/Makefile; do
  [[ -f "$root/$file" ]] || upstream_die "Missing R28S prerequisite: $file"
done
grep -q '^define Device/' "$root/$image" || upstream_die 'Unrecognized Rockchip image definitions'
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export REXWRT_UPSTREAM_CACHE=${REXWRT_UPSTREAM_CACHE:-$project/work/upstream-cache}
# An explicit source bundle permits offline replay of a previous discovery.
sources=${REXWRT_R28S_SOURCES:-$work/sources}
if [[ -z "${REXWRT_R28S_SOURCES:-}" ]]; then bash "$script_dir/discover.sh" "$sources"; fi
[[ -f "$sources/sources.json" && -s "$sources/sources.tsv" ]] || upstream_die 'Incomplete R28S source bundle'
bash "$script_dir/generate-kernel.sh" "$root" "$sources" "$work/kernel"
before=$work/before
after=$work/after
mkdir -p "$before" "$after"
for file in "$image" "$boarddir/01_leds" "$boarddir/02_network"; do
  mkdir -p "$before/$(dirname "$file")" "$after/$(dirname "$file")"
  cp "$root/$file" "$before/$file"
  cp "$root/$file" "$after/$file"
done

# Keep the R28S management AP available while LuCI adds or reconnects a station.
# Match the upstream statements so source drift stops the build before any edits.
patch_wifi_source() {
  local file=$1 anchor=$2 replacement=$3
  [[ -f "$root/$file" ]] || upstream_die "Missing R28S wireless source: $file"
  mkdir -p "$before/$(dirname "$file")" "$after/$(dirname "$file")"
  cp -p "$root/$file" "$before/$file"
  REXWRT_WIFI_ANCHOR="$anchor" REXWRT_WIFI_REPLACEMENT="$replacement" awk '
    BEGIN { anchor = ENVIRON["REXWRT_WIFI_ANCHOR"]; replacement = ENVIRON["REXWRT_WIFI_REPLACEMENT"] }
    {
      match($0, /^[[:blank:]]*/)
      indent = substr($0, 1, RLENGTH)
      if (substr($0, RLENGTH + 1) == anchor) {
        count++
        n = split(replacement, lines, "\n")
        for (i = 1; i <= n; i++) print indent lines[i]
      } else print
    }
    END { if (count != 1) exit 1 }
  ' "$before/$file" > "$work/wifi-source" || upstream_die "Unrecognized R28S wireless source: $file"
  cp -p "$before/$file" "$after/$file"
  cat "$work/wifi-source" > "$after/$file"
}

wifi_scripts=package/network/config/wifi-scripts
patch_wifi_source "$wifi_scripts/files/usr/share/hostap/common.uc" \
  'let reuse_ifname = find_reusable_wdev(phyidx);' \
  'let reuse_ifname = phy == "phy0" && data.mode == "sta" ? null : find_reusable_wdev(phyidx);'
patch_wifi_source "$wifi_scripts/files-ucode/lib/netifd/wireless/mac80211.sh" \
  'data.ap_start_disabled = true;' 'data.ap_start_disabled = data.phy != "phy0";'
patch_wifi_source package/network/services/hostapd/files/hostapd.uc \
  'if (!req.args.up) {' \
  $'if (!req.args.up) {\n\tif (phy == "phy0" && config.bss[0].ifname == "phy0-ap0")\n\t\treturn 0;'

bash "$script_dir/generate-packages.sh" "$sources" "$after"
kernel=$(cat "$work/kernel/kernel-version")
patch=target/linux/rockchip/patches-$kernel/999-rexwrt-r28s.patch
mkdir -p "$after/$(dirname "$patch")"
cp "$work/kernel/999-rexwrt-r28s.patch" "$after/$patch"

if grep -q '^define Device/friendlyarm_nanopi-r28s$' "$after/$image"; then
  # Preserve an upstream profile and its bootloader; add missing wireless packages.
  rm -rf "$after/package/boot/uboot-rexwrt-r28s"
  awk '
    /^define Device\/friendlyarm_nanopi-r28s$/ {active=1; count++}
    active && /^endef$/ {
      print "  DEVICE_PACKAGES += kmod-aic8800-sdio kmod-r28s-bluetooth bluez-daemon bluez-utils wpad-basic-mbedtls"
      active=0
    }
    {print}
    END {if (count!=1 || active) exit 1}
  ' "$after/$image" > "$work/image.mk" || upstream_die 'Cannot extend upstream R28S profile'
  mv "$work/image.mk" "$after/$image"
else
  grep -q '^define Device/rk3528$' "$after/$image" || upstream_die 'Missing upstream RK3528 image template'
  cat >> "$after/$image" <<'PROFILE'

define Device/friendlyarm_nanopi-r28s
  $(Device/rk3528)
  DEVICE_VENDOR := FriendlyElec
  DEVICE_MODEL := NanoPi R28S
  DEVICE_DTS := rk3528-nanopi-r28s
  UBOOT_DEVICE_NAME := rexwrt-r28s
  DEVICE_PACKAGES := u-boot-rexwrt-r28s kmod-r8169 kmod-gpio-button-hotplug \
	  kmod-aic8800-sdio kmod-r28s-bluetooth bluez-daemon bluez-utils wpad-basic-mbedtls
endef
TARGET_DEVICES += friendlyarm_nanopi-r28s
PROFILE
fi

# Add cases by function boundaries rather than a neighboring board or line number.
awk '
  {lines[NR]=$0}
  /^rockchip_setup_interfaces\(\)/ {mode="interfaces"}
  /^rockchip_setup_macs\(\)/ {mode="macs"}
  /case "\$board" in/ {start[mode]=NR}
  /friendlyarm,nanopi-r28s/ {present[mode]=1}
  END {
    if (!start["interfaces"] || !start["macs"]) exit 1
    for(i=1;i<=NR;i++) {
      print lines[i]
      if(i==start["interfaces"] && !present["interfaces"])
        print "\tfriendlyarm,nanopi-r28s)\n\t\tucidef_set_interfaces_lan_wan '\''eth1'\'' '\''eth0'\''\n\t\t;;"
      if(i==start["macs"] && !present["macs"])
        print "\tfriendlyarm,nanopi-r28s)\n\t\twan_mac=$(macaddr_generate_from_mmc_cid mmcblk*)\n\t\tlan_mac=$(macaddr_add \"$wan_mac\" 1)\n\t\t;;"
    }
  }
' "$after/$boarddir/02_network" > "$work/network" || upstream_die 'Unrecognized Rockchip network setup'
mv "$work/network" "$after/$boarddir/02_network"
if ! grep -q 'friendlyarm,nanopi-r28s' "$after/$boarddir/01_leds"; then
  awk '
    {print}
    /^case \$board in$/ {
      print "friendlyarm,nanopi-r28s)\n\tucidef_set_led_netdev \"wan\" \"WAN\" \"green:wan\" \"eth0\"\n\tucidef_set_led_netdev \"lan\" \"LAN\" \"green:lan\" \"eth1\"\n\t;;"
      count++
    }
    END {if(count!=1) exit 1}
  ' "$after/$boarddir/01_leds" > "$work/leds" || upstream_die 'Unrecognized Rockchip LED setup'
  mv "$work/leds" "$after/$boarddir/01_leds"
fi
sh -n "$after/$boarddir/01_leds"
sh -n "$after/$boarddir/02_network"
state=$after/.rexwrt/r28s
mkdir -p "$state"
cp "$sources/sources.json" "$sources/sources.tsv" "$work/kernel/kernel-release" "$state/"
# Bundle discovered inputs for replay without resolving moving branches again.
mkdir -p "$state/upstream"
cp -R "$sources/boot" "$sources/linux" "$state/upstream/"
cp "$sources/sources.json" "$sources/sources.tsv" "$sources/hci_aic.c" "$sources/vendor-board.dts" "$state/upstream/"
cp "$sources/vendor-soc.dtsi" "$state/upstream/"
if command -v sha256sum >/dev/null 2>&1; then digest=(sha256sum); else digest=(shasum -a 256); fi
(cd "$state/upstream" && find . -type f -exec "${digest[@]}" {} + | LC_ALL=C sort) > "$state/inputs.sha256"
status=0
(cd "$work" && git diff --binary --no-index --no-renames --src-prefix= --dst-prefix= before after) > "$work/adaptation.patch" || status=$?
[[ "$status" == 1 ]] || upstream_die 'Cannot generate complete R28S adaptation'
git -C "$root" apply --check "$work/adaptation.patch"
if (( dry_run )); then
  printf 'R28S dynamic adaptation validated for Linux %s (dry run).\n' "$(cat "$state/kernel-release")"
else
  git -C "$root" apply --whitespace=nowarn "$work/adaptation.patch"
  printf 'Applied dynamic R28S adaptation; sources recorded in %s/.rexwrt/r28s/\n' "$root"
fi
