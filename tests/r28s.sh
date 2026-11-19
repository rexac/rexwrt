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
printf 'request_module("aic8800_fdrv_sdio");\nh4_recv_buf(hu->hdev, skb, data, count, pkts, n);\n' > "$sources/hci_aic.c"
sha=1111111111111111111111111111111111111111
jq -n --arg sha "$sha" '{boot:$sha,aic:$sha,boot_repo:"u-boot/u-boot",boot_config:"nanopi-zero2-rk3528",ddr:"rk3528_ddr_fixture.bin",bl31:"rk3528_bl31_fixture.elf"}' > "$sources/sources.json"
printf 'u-boot/u-boot\tnext\t%s\n' "$sha" > "$sources/sources.tsv"
printf 'firmware\000fixture\n' > "$sources/boot/files/rk3528_ddr_fixture.bin"
printf 'firmware\000fixture\n' > "$sources/boot/files/rk3528_bl31_fixture.elf"
export REXWRT_R28S_SOURCES=$sources
for kernel in 6.99 7.11 7.12; do
  # Exercise both APIs and a changed declaration introduced by a target backport.
  h4_type=hci_dev h4_arg='hu->hdev'
  if [[ "$kernel" != 6.99 ]]; then h4_type=hci_uart; h4_arg=hu; fi
  if [[ "$kernel" == 7.12 ]]; then
    # A newer vendor implementation may already use the target UART argument.
    printf 'request_module("aic8800_fdrv_sdio");\nh4_recv_buf(hu, skb, data, count, pkts, n);\n' > "$sources/hci_aic.c"
  fi
  printf '#define HCI_UART_MAX_PROTO 13\nstruct sk_buff *h4_recv_buf(\n  struct %s *context, struct sk_buff *skb);\n' "$h4_type" > "$work/kernel/drivers/bluetooth/hci_uart.h"
  tree=$work/openwrt-$kernel
  boarddir=$tree/target/linux/rockchip/armv8/base-files/etc/board.d
  mkdir -p "$tree/include" "$tree/target/linux/rockchip/image" "$tree/target/linux/generic" "$tree/package/kernel/mac80211" "$boarddir"
  : > "$tree/include/toplevel.mk"
  printf 'KERNEL_PATCHVER:=%s\n' "$kernel" > "$tree/target/linux/rockchip/Makefile"
  printf 'LINUX_VERSION-%s = .7\n' "$kernel" > "$tree/target/linux/generic/kernel-$kernel"
  printf 'PKG_VERSION:=7.12.1\n' > "$tree/package/kernel/mac80211/Makefile"
  if [[ "$kernel" == 7.11 ]]; then
    printf 'PKG_SOURCE_VERSION:=7.12.1\nPKG_VERSION:=$(subst -,_,$(PKG_SOURCE_VERSION))\n' > "$tree/package/kernel/mac80211/Makefile"
  fi
  printf 'define Device/rk3528\n  SOC := rk3528\n  KERNEL_LOADADDR := 0x03000000\nendef\n' > "$tree/target/linux/rockchip/image/armv8.mk"
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
  if [[ "$kernel" == 6.99 ]]; then
    cp "$work/kernel/drivers/bluetooth/hci_uart.h" "$work/hci_uart.h"
    sed 's/struct hci_dev/struct unknown_context/' "$work/hci_uart.h" > "$work/kernel/drivers/bluetooth/hci_uart.h"
    if "$project/rexwrt" adapt --device nanopi-r28s --source "$tree" > "$work/error" 2>&1; then fail 'unknown H4 API accepted'; fi
    grep -q 'Unrecognized target h4_recv_buf API' "$work/error" || fail 'unknown H4 API diagnostic'
    manifest "$tree" > "$work/after"
    cmp "$work/before" "$work/after" || fail 'unknown H4 API modified checkout'
    mv "$work/hci_uart.h" "$work/kernel/drivers/bluetooth/hci_uart.h"
    rm -rf "$work/cache"
  fi
  "$project/rexwrt" adapt --device nanopi-r28s --source "$tree" --dry-run > "$work/log"
  manifest "$tree" > "$work/after"
  cmp "$work/before" "$work/after" || fail 'dry run modified checkout'
  "$project/rexwrt" adapt --device nanopi-r28s --source "$tree" > "$work/log"
  if [[ "$kernel" == 7.12 ]]; then
    grep -q 'UBOOT_DEVICE_NAME := upstream-r28s' "$tree/target/linux/rockchip/image/armv8.mk" || fail 'upstream boot selection changed'
    [[ ! -d "$tree/package/boot/uboot-rexwrt-r28s" ]] || fail 'redundant boot package generated'
  else
    # Evaluate the generated profile: setting SOC alone leaves FIT addresses empty.
    addresses=$(make --no-print-directory -s -f - PROFILE_FILE="$tree/target/linux/rockchip/image/armv8.mk" <<'MAKE'
include $(PROFILE_FILE)
$(eval $(Device/friendlyarm_nanopi-r28s))
.PHONY: inspect
inspect:
	@printf '%s %s %s\n' '$(SOC)' '$(KERNEL_LOADADDR)' '$(if $(KERNEL_ENTRY),$(KERNEL_ENTRY),$(KERNEL_LOADADDR))'
MAKE
    )
    [[ "$addresses" == 'rk3528 0x03000000 0x03000000' ]] || fail "invalid FIT addresses: $addresses"
    grep -q 'u-boot-rexwrt-r28s' "$tree/target/linux/rockchip/image/armv8.mk" || fail 'boot package selection'
    grep -q 'https://github.com/u-boot/u-boot.git' "$tree/package/boot/uboot-rexwrt-r28s/Makefile" || fail 'official boot source'
    cmp "$sources/boot/files/rk3528_ddr_fixture.bin" "$tree/package/boot/uboot-rexwrt-r28s/files/rk3528_ddr_fixture.bin" || fail 'binary firmware damaged'
  fi
  grep -q 'request_module("aic8800_fdrv")' "$tree/target/linux/rockchip/patches-$kernel/999-rexwrt-r28s.patch" || fail 'Bluetooth module linkage'
  grep -F "h4_recv_buf($h4_arg, skb" "$tree/target/linux/rockchip/patches-$kernel/999-rexwrt-r28s.patch" >/dev/null || fail 'Bluetooth H4 receive API'
  # Snapshot uses a Make expression for PKG_VERSION; metadata parsing must still
  # expose the Wi-Fi and Bluetooth packages rather than silently dropping them.
  awk '/^CFG80211_VERSION:=/ { active=1 } active { print } active && /^endif/ { exit }' \
    "$tree/package/kernel/aic8800-sdio/Makefile" > "$work/version.mk"
  printf '\ninspect:\n\t@echo $(CFG80211_VERSION)\n' >> "$work/version.mk"
  version=$(make --no-print-directory -s -f "$work/version.mk" TOPDIR="$tree" inspect)
  [[ "$version" == "$((7*65536+12*256+1))" ]] || fail "wireless metadata version: $version"
  grep -q 'kmod-aic8800-sdio' "$tree/target/linux/rockchip/image/armv8.mk" || fail 'wireless package selection'
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
cfg80211_rx_unexpected_4addr_frame(dev,
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 17, 0)
addr, GFP_ATOMIC);
#else
addr, -1, GFP_ATOMIC);
#endif
cfg80211_rx_mgmt(dev,
channel,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 12, 0)
link,
#endif
data);
cfg80211_optional_args(dev,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 3, 0)
first,
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0)
second,
#endif
data);
int wireless_callback(struct wiphy *wiphy,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 1, 0)
struct wireless_dev *wdev,
#else
struct net_device *dev,
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 2, 0)
int argument,
#endif
int value);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 1, 0)
struct net_device *dev = wdev->netdev;
#endif
cfg80211_complete(dev);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 16, 0)
timer_delete_sync(&timer);
#endif
cfg80211_complete(dev);
#ifdef CONFIG_TIMER_HELPER
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 18, 0)
timer_shutdown_sync(&timer);
#endif
#endif
C
awk -f "$project/devices/nanopi-r28s/wireless-guards.awk" "$work/guards.c" > "$work/guards.out"
grep -q '#if CFG80211_VERSION >= KERNEL_VERSION(6, 17, 0)' "$work/guards.out" || fail 'wireless version guard'
grep -q '#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)' "$work/guards.out" || fail 'timer version guard changed'
grep -q '#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 13, 0)' "$work/guards.out" || fail 'VFS version guard changed'
grep -q '#if CFG80211_VERSION >= KERNEL_VERSION(6, 14, 0)' "$work/guards.out" || fail 'enclosing wireless guard unchanged'
grep -q '#if CFG80211_VERSION >= KERNEL_VERSION(6, 10, 0)' "$work/guards.out" || fail 'optional wireless callback argument guard unchanged'
grep -q '#if CFG80211_VERSION < KERNEL_VERSION(6, 17, 0)' "$work/guards.out" || fail 'optional wireless call argument guard unchanged'
grep -q '#if CFG80211_VERSION >= KERNEL_VERSION(6, 12, 0)' "$work/guards.out" || fail 'multiline wireless call argument guard unchanged'
grep -q '#if CFG80211_VERSION >= KERNEL_VERSION(6, 4, 0)' "$work/guards.out" || fail 'sibling wireless call argument guard unchanged'
grep -q '#if CFG80211_VERSION >= KERNEL_VERSION(7, 2, 0)' "$work/guards.out" || fail 'sibling wireless callback argument guard unchanged'
[[ $(grep -c '#if CFG80211_VERSION >= KERNEL_VERSION(7, 1, 0)' "$work/guards.out") == 2 ]] || fail 'wireless device API body guard unchanged'
grep -q '#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 16, 0)' "$work/guards.out" || fail 'preceding wireless statement changed timer guard'
grep -q '#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 18, 0)' "$work/guards.out" || fail 'preceding wireless statement crossed preprocessor boundary'
printf 'PASS: wireless and core-kernel version guards remain independent\n'

# Keep shared prototypes unique when upstream provides none, some or all of them.
for supplied in 0 2 4; do
  source_root=$work/radxa-$supplied
  driver=$source_root/src/SDIO/driver_fw/driver/aic8800/aic8800_fdrv
  mkdir -p "$source_root/debian/patches" "$source_root/src/SDIO/driver_fw/fw/aic8800D80" "$driver"
  : > "$source_root/debian/patches/series"
  cat > "$driver/rwnx_main.c" <<'C'
switch (action_code) {
case WLAN_TDLS_SETUP_RESPONSE:
    if (active)
        status_code = WLAN_STATUS_REQUEST_DECLINED;
    /* fall-through */
case WLAN_TDLS_SETUP_REQUEST:
    send_mgmt(status_code);
    break;
}
C
  cat > "$driver/rwnx_rx.c" <<'C'
it_present = &rtap->it_present;
pos = (void *)(it_present + 1);
struct ieee80211_radiotap_he he;
memcpy(pos, &he, sizeof(he));
C
  : > "${driver%/*}/Makefile"
  printf 'void cmd_mgr_task_process(struct work_struct *work)\n{\n}\n' > "$driver/rwnx_cmds.c"
  {
    printf '#ifndef _RWNX_IPC_UTILS_H_\n#define _RWNX_IPC_UTILS_H_\nstruct rwnx_hw;\n'
    if (( supplied )); then printf 'int rwnx_init_aic(struct rwnx_hw *rwnx_hw);\n'; fi
    printf '#endif\n'
  } > "$driver/rwnx_utils.h"
  cat > "$work/prototypes" <<'HEADER'
struct rwnx_cmd *rwnx_cmd_malloc(void);
void rwnx_cmd_free(struct rwnx_cmd *cmd);
int rwnx_init_cmd_array(void);
void rwnx_free_cmd_array(void);
HEADER
  {
    printf '#ifndef _RWNX_CMDS_H_\n#define _RWNX_CMDS_H_\nstruct rwnx_cmd;\n'
    if (( supplied )); then head -n "$supplied" "$work/prototypes"; fi
    printf '#endif\n'
  } > "$driver/rwnx_cmds.h"
  for attempt in 1 2; do
    bash "$project/devices/nanopi-r28s/prepare-wireless.sh" "$source_root"
    while IFS= read -r declaration; do
      [[ $(grep -Fxc "$declaration" "$driver/rwnx_cmds.h") == 1 ]] || fail "missing or duplicate prototype: $declaration"
    done < "$work/prototypes"
    [[ $(grep -Fxc 'int rwnx_init_aic(struct rwnx_hw *rwnx_hw);' "$driver/rwnx_utils.h") == 1 ]] || fail 'missing or duplicate initialization prototype'
    grep -q '^static void cmd_mgr_task_process(' "$driver/rwnx_cmds.c" || fail 'workqueue callback is not private'
    [[ $(grep -Fxc 'subdir-ccflags-y += -Wno-error=missing-prototypes' "${driver%/*}/Makefile") == 1 ]] || fail 'vendor diagnostic scope or duplication'
    grep -Fq 'it_present = (__le32 *)(skb->data + offsetof(struct ieee80211_radiotap_header, it_present));' "$driver/rwnx_rx.c" || fail 'radiotap cursor does not originate in skb allocation'
    grep -Fq 'struct ieee80211_radiotap_he he = {0};' "$driver/rwnx_rx.c" || fail 'radiotap HE fields are not initialized'
    grep -Fq 'memcpy(pos, &he, sizeof(he));' "$driver/rwnx_rx.c" || fail 'radiotap fortified copy was replaced'
    awk '
      /fallthrough;/ { marked++; if (getline <= 0 || $0 !~ /^case WLAN_TDLS_SETUP_REQUEST:/) exit 1 }
      END { if (marked != 1) exit 1 }
    ' "$driver/rwnx_main.c" || fail 'TDLS response does not explicitly fall through into request handling'
  done
done
printf 'PASS: Radxa shared API declarations and private callback cover missing, partial and upstream-fixed sources\n'
