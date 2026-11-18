#!/usr/bin/env bash
# Generate isolated OpenWrt packages from this build's discovered revisions.
set -euo pipefail
sources=${1:?Discovered sources required}
output=${2:?Output directory required}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/../../scripts/lib/upstream.sh"
for key in boot aic; do
  value=$(jq -er ".$key" "$sources/sources.json")
  [[ "$value" =~ ^[0-9a-f]{40}$ ]] || upstream_die "Invalid $key source revision"
done
[[ $(jq -r .boot_repo "$sources/sources.json") == u-boot/u-boot ]] || upstream_die 'Boot source must be the official U-Boot repository'
[[ $(jq -r .aic_repo "$sources/sources.json") == friendlyarm/aic8800 ]] || upstream_die 'Wireless source must be official FriendlyElec; rediscover older source bundles'
boot=$(jq -r .boot "$sources/sources.json")
aic=$(jq -r .aic "$sources/sources.json")
bootconfig=$(jq -r .boot_config "$sources/sources.json")
ddr=$(jq -r .ddr "$sources/sources.json")
bl31=$(jq -r .bl31 "$sources/sources.json")
[[ "$bootconfig" =~ ^[a-zA-Z0-9_-]+$ ]] || upstream_die 'Invalid U-Boot configuration'
[[ "$ddr" =~ ^rk3528_[a-zA-Z0-9_.-]+\.bin$ && "$bl31" =~ ^rk3528_[a-zA-Z0-9_.-]+\.elf$ ]] || upstream_die 'Invalid boot firmware names'
for name in "$ddr" "$bl31"; do [[ -s "$sources/boot/files/$name" ]] || upstream_die "Missing firmware: $name"; done
bootdir=$output/package/boot/uboot-rexwrt-r28s
wifidir=$output/package/kernel/aic8800-sdio
mkdir -p "$bootdir/files" "$wifidir"
cp "$sources/boot/files/$ddr" "$sources/boot/files/$bl31" "$bootdir/files/"
sed -e "s/@BOOT@/$boot/g" -e "s/@BOOTCONFIG@/$bootconfig/g" -e "s/@DDR@/$ddr/g" -e "s/@BL31@/$bl31/g" \
  "$script_dir/templates/uboot.mk" > "$bootdir/Makefile"
sed "s/@AIC@/$aic/g" "$script_dir/templates/wireless.mk" > "$wifidir/Makefile"
cp "$script_dir/prepare-wireless.sh" "$wifidir/prepare.sh"
cp "$script_dir/wireless-guards.awk" "$wifidir/"
