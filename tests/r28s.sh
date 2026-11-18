#!/usr/bin/env bash
# Exercise generated ports without network or version-specific board patches.
set -euo pipefail
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
manifest() { (cd "$1" && find . -type f -exec shasum -a 256 {} + | LC_ALL=C sort); }
mkdir -p "$work/bin" "$work/kernel/drivers/bluetooth" "$work/kernel/arch/arm64/boot/dts/rockchip"
cat > "$work/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
url= output=
while (( $# )); do
  case "$1" in
    https://*) url=$1 ;;
    -o) output=$2; shift ;;
  esac
  shift
done
[[ -n "$url" && -n "$output" ]]
case "$url" in
  */drivers/bluetooth/*) file=drivers/bluetooth/${url##*/} ;;
  */arch/arm64/boot/dts/rockchip/Makefile) file=arch/arm64/boot/dts/rockchip/Makefile ;;
  *) printf '404'; exit 0 ;;
esac
if [[ ${R28S_MISSING_KERNEL:-0} == 1 ]]; then printf '404'; else cp "$R28S_KERNEL/$file" "$output"; printf '200'; fi
MOCK
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH" R28S_KERNEL=$work/kernel REXWRT_UPSTREAM_CACHE=$work/cache
printf '#define HCI_UART_MAX_PROTO 13\n' > "$work/kernel/drivers/bluetooth/hci_uart.h"
cat > "$work/kernel/drivers/bluetooth/hci_ldisc.c" <<'KERNEL'
#ifdef CONFIG_BT_HCIUART_MRVL
	mrvl_init();
#endif
#ifdef CONFIG_BT_HCIUART_MRVL
	mrvl_deinit();
#endif
KERNEL
: > "$work/kernel/drivers/bluetooth/Makefile"
: > "$work/kernel/drivers/bluetooth/Kconfig"
: > "$work/kernel/arch/arm64/boot/dts/rockchip/Makefile"
sources=$work/sources
mkdir -p "$sources/linux" "$sources/boot/files"
cat > "$sources/linux/rk3528-nanopi-r28s.dts" <<'DTS'
/dts-v1/;
/ {
 gpio-keys {
  button-user {
   linux,code = <BTN_1>;
  };
 };
};
&leds {
};
DTS
: > "$sources/linux/rk3528-nanopi.dtsi"
cat > "$sources/vendor-board.dts" <<'DTS'
&uart2 {
 bluetooth {
  compatible = "cvte,aic8800-bt";
 };
};
DTS
printf 'request_module("aic8800_fdrv");\n' > "$sources/hci_aic.c"
sha=1111111111111111111111111111111111111111
jq -n --arg sha "$sha" '{boot:$sha,aic:$sha,aic_repo:"friendlyarm/aic8800",boot_repo:"u-boot/u-boot",boot_config:"nanopi-zero2-rk3528",ddr:"rk3528_ddr_fixture.bin",bl31:"rk3528_bl31_fixture.elf"}' > "$sources/sources.json"
printf 'u-boot/u-boot\tnext\t%s\n' "$sha" > "$sources/sources.tsv"
printf 'firmware\000fixture\n' > "$sources/boot/files/rk3528_ddr_fixture.bin"
printf 'firmware\000fixture\n' > "$sources/boot/files/rk3528_bl31_fixture.elf"
export REXWRT_R28S_SOURCES=$sources
for kernel in 6.99 7.11 7.12; do
  tree=$work/openwrt-$kernel
  boarddir=$tree/target/linux/rockchip/armv8/base-files/etc/board.d
  mkdir -p "$tree/include" "$tree/target/linux/rockchip/image" "$tree/target/linux/generic" "$tree/package/kernel/mac80211" "$boarddir"
  : > "$tree/include/toplevel.mk"
  printf 'KERNEL_PATCHVER:=%s\n' "$kernel" > "$tree/target/linux/rockchip/Makefile"
  printf 'LINUX_VERSION-%s = .7\n' "$kernel" > "$tree/target/linux/generic/kernel-$kernel"
  printf 'PKG_VERSION:=7.12.1\n' > "$tree/package/kernel/mac80211/Makefile"
  printf 'define Device/existing\nendef\n' > "$tree/target/linux/rockchip/image/armv8.mk"
  if [[ "$kernel" == 7.12 ]]; then
    printf 'define Device/friendlyarm_nanopi-r28s\n  UBOOT_DEVICE_NAME := upstream-r28s\nendef\n' >> "$tree/target/linux/rockchip/image/armv8.mk"
  fi
  cat > "$boarddir/02_network" <<'NETWORK'
rockchip_setup_interfaces()
{
 case "$board" in
 *) ;;
 esac
}
rockchip_setup_macs()
{
 case "$board" in
 *) ;;
 esac
}
NETWORK
  printf 'case $board in\n*) ;;\nesac\n' > "$boarddir/01_leds"
  manifest "$tree" > "$work/before"
  if R28S_MISSING_KERNEL=1 "$project/rexwrt" adapt --device nanopi-r28s --source "$tree" > "$work/error" 2>&1; then fail 'missing kernel accepted'; fi
  manifest "$tree" > "$work/after"
  cmp "$work/before" "$work/after" || fail 'failure modified checkout'
  # Do not retain the deliberately missing immutable files between fixtures.
  rm -rf "$work/cache"
  "$project/rexwrt" adapt --device nanopi-r28s --source "$tree" --dry-run > "$work/log"
  manifest "$tree" > "$work/after"
  cmp "$work/before" "$work/after" || fail 'dry run modified checkout'
  "$project/rexwrt" adapt --device nanopi-r28s --source "$tree" > "$work/log"
  if [[ "$kernel" == 7.12 ]]; then
    grep -q 'UBOOT_DEVICE_NAME := upstream-r28s' "$tree/target/linux/rockchip/image/armv8.mk" || fail 'upstream boot selection changed'
    [[ ! -d "$tree/package/boot/uboot-rexwrt-r28s" ]] || fail 'redundant boot package generated'
  else
    grep -q 'u-boot-rexwrt-r28s' "$tree/target/linux/rockchip/image/armv8.mk" || fail 'boot package selection'
    grep -q 'https://github.com/u-boot/u-boot.git' "$tree/package/boot/uboot-rexwrt-r28s/Makefile" || fail 'official boot source'
    cmp "$sources/boot/files/rk3528_ddr_fixture.bin" "$tree/package/boot/uboot-rexwrt-r28s/files/rk3528_ddr_fixture.bin" || fail 'binary firmware damaged'
  fi
  grep -q 'request_module("aic8800_fdrv")' "$tree/target/linux/rockchip/patches-$kernel/999-rexwrt-r28s.patch" || fail 'Bluetooth module linkage'
  grep -q 'kmod-aic8800-sdio' "$tree/target/linux/rockchip/image/armv8.mk" || fail 'wireless package selection'
  grep -q 'https://github.com/friendlyarm/aic8800.git' "$tree/package/kernel/aic8800-sdio/Makefile" || fail 'official wireless source'
  grep -q 'CONFIG_AIC_FW_PATH=/lib/firmware/aic' "$tree/package/kernel/aic8800-sdio/Makefile" || fail 'official firmware path'
  manifest "$tree" > "$work/before"
  "$project/rexwrt" adapt --device nanopi-r28s --source "$tree" > "$work/log"
  manifest "$tree" > "$work/after"
  cmp "$work/before" "$work/after" || fail 'repeat modified checkout'
  printf 'PASS: R28S Linux %s failure isolation, dry run, binary firmware and idempotence\n' "$kernel"
done

# A wireless API guard must change without changing a nested timer or VFS guard.
cat > "$work/guards.c" <<'C'
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0)
cfg80211_set_tx_power(wiphy, radio_idx);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
timer_delete_sync(&timer);
#else
del_timer_sync(&timer);
#endif
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 13, 0)
MODULE_IMPORT_NS("VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver");
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 14, 0)
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0)
cfg80211_set_tx_power(wiphy, radio_idx);
#endif
#endif
int cfg80211_callback(struct wiphy *wiphy,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 10, 0)
struct net_device *dev,
#endif
int value);
C
awk -f "$project/devices/nanopi-r28s/wireless-guards.awk" "$work/guards.c" > "$work/guards.out"
grep -q '#if CFG80211_VERSION >= KERNEL_VERSION(6, 17, 0)' "$work/guards.out" || fail 'wireless version guard'
grep -q '#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)' "$work/guards.out" || fail 'timer version guard changed'
grep -q '#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 13, 0)' "$work/guards.out" || fail 'VFS version guard changed'
grep -q '#if CFG80211_VERSION >= KERNEL_VERSION(6, 14, 0)' "$work/guards.out" || fail 'enclosing wireless guard unchanged'
grep -q '#if CFG80211_VERSION >= KERNEL_VERSION(6, 10, 0)' "$work/guards.out" || fail 'optional wireless callback argument guard unchanged'
printf 'PASS: wireless and core-kernel version guards remain independent\n'

# Stable and snapshot may share wireless headers while using different kernels.
mkdir -p "$work/driver/aic8800_fdrv" "$work/driver/aic8800_bsp" "$work/driver/fw/aic8800D80" "$work/headers/include/linux"
cat > "$work/cfg80211.h" <<'C'
int (*set_tx_power)(struct wiphy *wiphy, struct wireless_dev *wdev, int radio_idx, int type);
int (*set_wiphy_params)(struct wiphy *wiphy, int radio_idx, u32 changed);
int (*set_monitor_channel)(struct wiphy *wiphy, struct net_device *dev, void *chandef);
C
cat > "$work/driver.c" <<'C'
static int rwnx_cfg80211_set_tx_power(struct wiphy *wiphy, struct wireless_dev *wdev,
int type, int mbm) { return 0; }
static int rwnx_cfg80211_set_wiphy_params(struct wiphy *wiphy, u32 changed) { return 0; }
static int rwnx_cfg80211_set_monitor_channel(struct wiphy *wiphy,
struct cfg80211_chan_def *chandef) { return 0; }
rwnx_cfg80211_set_monitor_channel(wiphy, NULL);
del_timer_sync(&timer);
MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver);
C
for api in legacy current; do
  cp "$work/driver.c" "$work/driver/aic8800_fdrv/rwnx_main.c"
  if [[ "$api" == legacy ]]; then
    printf 'int del_timer_sync(struct timer_list *timer);\n' > "$work/headers/include/linux/timer.h"
    printf '#define MODULE_IMPORT_NS(ns) MODULE_INFO(import_ns, __stringify(ns))\n' > "$work/headers/include/linux/module.h"
  else
    printf 'int timer_delete_sync(struct timer_list *timer);\n' > "$work/headers/include/linux/timer.h"
    printf '#define MODULE_IMPORT_NS(ns) MODULE_INFO(import_ns, ns)\n' > "$work/headers/include/linux/module.h"
  fi
  bash "$project/devices/nanopi-r28s/prepare-wireless.sh" "$work/driver" "$work/headers" "$work/cfg80211.h"
  result=$work/driver/aic8800_fdrv/rwnx_main.c
  grep -q 'int radio_idx,' "$result" || fail 'wireless radio argument missing'
  grep -q 'int radio_idx, u32 changed' "$result" || fail 'wiphy radio argument missing'
  grep -q 'struct net_device \*dev,' "$result" || fail 'monitor device argument missing'
  grep -q 'rwnx_cfg80211_set_monitor_channel(wiphy, NULL, NULL)' "$result" || fail 'internal monitor call not adapted'
  if [[ "$api" == legacy ]]; then
    grep -q 'del_timer_sync(&timer)' "$result" || fail 'legacy timer call changed'
    grep -q 'MODULE_IMPORT_NS(VFS_' "$result" || fail 'legacy namespace syntax changed'
  else
    grep -q 'timer_delete_sync(&timer)' "$result" || fail 'current timer call missing'
    grep -q 'MODULE_IMPORT_NS("VFS_' "$result" || fail 'current namespace not quoted'
  fi
  cp "$result" "$work/prepared.c"
  bash "$project/devices/nanopi-r28s/prepare-wireless.sh" "$work/driver" "$work/headers" "$work/cfg80211.h"
  cmp "$result" "$work/prepared.c" || fail 'repeat driver configuration changed sources'
done
printf 'PASS: FriendlyElec driver adaptation follows wireless and core header APIs independently\n'
