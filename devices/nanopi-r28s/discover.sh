#!/usr/bin/env bash
# Resolve official moving branches once without executing downloaded scripts.
set -euo pipefail
work=${1:?Output directory required}
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$project/scripts/lib/upstream.sh"
mkdir -p "$work"
export UPSTREAM_MANIFEST=$work/sources.tsv
: > "$UPSTREAM_MANIFEST"
linux=$(upstream_head torvalds/linux master "$work/linux-head.json")
# The repository default still points to an older release; follow the newest
# published FriendlyWrt release branch and its RK3528 manifest instead.
manifestbranch=$(git ls-remote --heads https://github.com/friendlyarm/friendlywrt_manifests.git 'refs/heads/master-v*' | awk -F/ '
  $NF ~ /^master-v[0-9]+\.[0-9]+$/ {
    branch=$NF; sub(/^master-v/, "", branch); split(branch, version, "[.]")
    if (version[1]+0 > major || (version[1]+0 == major && version[2]+0 > minor)) {
      major=version[1]+0; minor=version[2]+0; selected=$NF
    }
  }
  END {print selected}
')
[[ "$manifestbranch" =~ ^master-v[0-9]+\.[0-9]+$ ]] || upstream_die 'Cannot discover the latest FriendlyWrt release branch'
manifest=$(upstream_head friendlyarm/friendlywrt_manifests "$manifestbranch" "$work/friendlywrt-head.json")
upstream_required_file friendlyarm/friendlywrt_manifests "$manifest" rk3528.xml "$work/rk3528.xml"
vendorbranch=$(sed -nE 's@.*name="kernel-rockchip".*revision="refs/heads/([^"]+)".*@\1@p' "$work/rk3528.xml")
fusebranch=$(sed -nE 's@.*name="sd-fuse_rk3528".*revision="refs/heads/([^"]+)".*@\1@p' "$work/rk3528.xml")
[[ "$vendorbranch" =~ ^[a-zA-Z0-9._/-]+$ && "$fusebranch" =~ ^[a-zA-Z0-9._/-]+$ ]] || upstream_die 'Unrecognized FriendlyWrt RK3528 manifest'
fuse=$(upstream_head friendlyarm/sd-fuse_rk3528 "$fusebranch" "$work/sd-fuse-head.json")
upstream_required_file friendlyarm/sd-fuse_rk3528 "$fuse" build-kernel.sh "$work/build-kernel.sh"
grep -Eq 'git clone https://github.com/friendlyarm/aic8800 -b main( |$)' "$work/build-kernel.sh" || upstream_die 'FriendlyWrt wireless provider changed'
grep -q 'CONFIG_AIC_FW_PATH=/lib/firmware/aic' "$work/build-kernel.sh" || upstream_die 'FriendlyWrt firmware layout changed'
aic=$(upstream_head friendlyarm/aic8800 main "$work/aic-head.json")
vendorsha=$(upstream_head friendlyarm/kernel-rockchip "$vendorbranch" "$work/vendor-head.json")
upstream_required_file friendlyarm/kernel-rockchip "$vendorsha" drivers/bluetooth/hci_aic.c "$work/hci_aic.c"
upstream_required_file friendlyarm/kernel-rockchip "$vendorsha" arch/arm64/boot/dts/rockchip/rk3528-nanopi-rev03.dts "$work/vendor-board.dts"
grep -q 'friendlyelec,nanopi-r28s' "$work/vendor-board.dts" || upstream_die 'FriendlyElec R28S board identity changed'
for name in rk3528-nanopi-r28s.dts rk3528-nanopi.dtsi; do
  upstream_required_file torvalds/linux "$linux" "arch/arm64/boot/dts/rockchip/$name" "$work/linux/$name"
done
# Prefer main; use the official integration branch only while main lacks R28S.
bootbranch=main
boot=$(upstream_head u-boot/u-boot "$bootbranch" "$work/boot-main-head.json")
if ! upstream_file u-boot/u-boot "$boot" arch/arm/dts/rk3528-nanopi-r28s-u-boot.dtsi "$work/boot-support.dtsi"; then
  bootbranch=next
  boot=$(upstream_head u-boot/u-boot "$bootbranch" "$work/boot-next-head.json")
  upstream_required_file u-boot/u-boot "$boot" arch/arm/dts/rk3528-nanopi-r28s-u-boot.dtsi "$work/boot-support.dtsi"
fi
bootconfig=nanopi-zero2-rk3528
mkdir -p "$work/boot/files"
upstream_required_file u-boot/u-boot "$boot" "configs/${bootconfig}_defconfig" "$work/boot/files/defconfig"
grep -q 'rk3528-nanopi-r28s' "$work/boot/files/defconfig" || upstream_die 'Official U-Boot configuration no longer includes R28S'
# Follow the firmware names used by OpenWrt's current official RK3528 package.
openwrt=$(upstream_head openwrt/openwrt main "$work/openwrt-head.json")
upstream_required_file openwrt/openwrt "$openwrt" package/boot/uboot-rockchip/Makefile "$work/openwrt-uboot.mk"
awk '/^define U-Boot\/rk3528\/Default$/ {active=1; next} active && /^endef$/ {exit} active {print}' "$work/openwrt-uboot.mk" > "$work/rk3528-boot.mk"
ddr=$(sed -nE 's/^[[:space:]]*TPL[[:space:]]*:=[[:space:]]*([^[:space:]]+).*$/\1/p' "$work/rk3528-boot.mk")
bl31=$(sed -nE 's/^[[:space:]]*ATF[[:space:]]*:=[[:space:]]*([^[:space:]]+).*$/\1/p' "$work/rk3528-boot.mk")
[[ "$ddr" =~ ^rk3528_[a-zA-Z0-9_.-]+\.bin$ && "$bl31" =~ ^rk3528_[a-zA-Z0-9_.-]+\.elf$ ]] || upstream_die 'Cannot discover OpenWrt RK3528 firmware names'
upstream_required_file openwrt/openwrt "$openwrt" package/boot/rkbin/Makefile "$work/openwrt-rkbin.mk"
# Firmware names and revision form one upstream-selected set; do not mix releases.
rkbin=$(sed -n 's/^PKG_SOURCE_VERSION:=//p' "$work/openwrt-rkbin.mk")
[[ "$rkbin" =~ ^[0-9a-f]{40}$ ]] || upstream_die 'Cannot discover the OpenWrt-selected rkbin revision'
printf 'rockchip-linux/rkbin\topenwrt-selected\t%s\n' "$rkbin" >> "$UPSTREAM_MANIFEST"
for name in "$ddr" "$bl31"; do upstream_required_file rockchip-linux/rkbin "$rkbin" "bin/rk35/$name" "$work/boot/files/$name"; done
jq -n --arg manifest "$manifest" --arg manifestbranch "$manifestbranch" --arg fuse "$fuse" --arg fusebranch "$fusebranch" \
  --arg linux "$linux" --arg aic "$aic" \
  --arg boot "$boot" --arg bootbranch "$bootbranch" --arg bootconfig "$bootconfig" \
  --arg vendor "$vendorsha" --arg vendorbranch "$vendorbranch" --arg rkbin "$rkbin" \
  --arg ddr "$ddr" --arg bl31 "$bl31" --arg openwrt "$openwrt" \
  '{friendlywrt:$manifest,friendlywrt_branch:$manifestbranch,sd_fuse:$fuse,sd_fuse_branch:$fusebranch,
    linux:$linux,aic:$aic,aic_repo:"friendlyarm/aic8800",aic_branch:"main",
    boot:$boot,boot_repo:"u-boot/u-boot",boot_branch:$bootbranch,boot_config:$bootconfig,
    vendor:$vendor,vendor_repo:"friendlyarm/kernel-rockchip",vendor_branch:$vendorbranch,
    rkbin:$rkbin,ddr:$ddr,bl31:$bl31,openwrt:$openwrt}' > "$work/sources.json"
printf 'Discovered R28S sources; official U-Boot branch: %s\n' "$bootbranch"
