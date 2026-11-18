#!/usr/bin/env bash
# Resolve official moving branches once without executing downloaded scripts.
set -euo pipefail
work=${1:?Output directory required}
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$project/scripts/lib/upstream.sh"
mkdir -p "$work"
export UPSTREAM_MANIFEST=$work/sources.tsv
: > "$UPSTREAM_MANIFEST"
armbian=$(upstream_head armbian/build main "$work/armbian-head.json")
linux=$(upstream_head torvalds/linux master "$work/linux-head.json")
aic=$(upstream_head radxa-pkg/aic8800 main "$work/aic-head.json")
get_armbian() { upstream_required_file armbian/build "$armbian" "$1" "$work/armbian/$1"; }
board=config/boards/nanopi-r28s.csc
vendor=config/sources/families/include/rockchip_vendor_common.inc
for path in "$board" "$vendor" extensions/radxa-aic8800.sh; do get_armbian "$path"; done
[[ $(upstream_setting "$work/armbian/$board" AIC8800_TYPE) == sdio ]] || upstream_die 'R28S wireless bus changed upstream'
grep -q 'enable_extension "radxa-aic8800"' "$work/armbian/$board" || upstream_die 'Armbian wireless provider changed'
[[ $(upstream_setting "$work/armbian/$board" KERNEL_TARGET) == vendor ]] || upstream_die 'Armbian kernel family changed; review discovery rules'
vendorbranch=$(awk '/^[[:space:]]*vendor\)/ {active=1; next} active && /KERNELBRANCH=/ {sub(/^.*branch:/, ""); sub(/["\047].*$/, ""); print; exit}' "$work/armbian/$vendor")
[[ "$vendorbranch" =~ ^[a-zA-Z0-9._/-]+$ ]] || upstream_die 'Cannot discover Armbian vendor kernel branch'
vendorsha=$(upstream_head armbian/linux-rockchip "$vendorbranch" "$work/vendor-head.json")
upstream_required_file armbian/linux-rockchip "$vendorsha" drivers/bluetooth/hci_aic.c "$work/hci_aic.c"
fdt=$(upstream_setting "$work/armbian/$board" BOOT_FDT_FILE)
upstream_required_file armbian/linux-rockchip "$vendorsha" "arch/arm64/boot/dts/${fdt%.dtb}.dts" "$work/vendor-board.dts"
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
jq -n --arg armbian "$armbian" --arg linux "$linux" --arg aic "$aic" \
  --arg boot "$boot" --arg bootbranch "$bootbranch" --arg bootconfig "$bootconfig" \
  --arg vendor "$vendorsha" --arg vendorbranch "$vendorbranch" --arg rkbin "$rkbin" \
  --arg ddr "$ddr" --arg bl31 "$bl31" --arg openwrt "$openwrt" \
  '{armbian:$armbian,linux:$linux,aic:$aic,aic_repo:"radxa-pkg/aic8800",aic_branch:"main",boot:$boot,boot_repo:"u-boot/u-boot",boot_branch:$bootbranch,boot_config:$bootconfig,vendor:$vendor,vendor_repo:"armbian/linux-rockchip",vendor_branch:$vendorbranch,rkbin:$rkbin,ddr:$ddr,bl31:$bl31,openwrt:$openwrt}' > "$work/sources.json"
printf 'Discovered R28S sources; official U-Boot branch: %s\n' "$bootbranch"
