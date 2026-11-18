#!/usr/bin/env bash
# Reconstruct affected target-kernel files, then generate one contextual patch.
set -euo pipefail
root=${1:?OpenWrt tree required}
sources=${2:?Discovered sources required}
output=${3:?Output directory required}
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$project/scripts/lib/upstream.sh"
kernel=$(sed -n 's/^KERNEL_PATCHVER:=//p' "$root/target/linux/rockchip/Makefile")
[[ "$kernel" =~ ^[0-9]+\.[0-9]+$ ]] || upstream_die 'Cannot detect Rockchip kernel version'
version_file=$root/target/linux/generic/kernel-$kernel
[[ -f "$version_file" ]] || version_file=$root/include/kernel-$kernel
minor=$(sed -nE "s/^LINUX_VERSION-$kernel[[:space:]]*[:?]?=[[:space:]]*(\.[0-9]+)[[:space:]]*$/\\1/p" "$version_file")
[[ "$minor" =~ ^\.[0-9]+$ ]] || upstream_die 'Cannot detect the exact OpenWrt kernel release'
release=$kernel$minor
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
before=$work/before
after=$work/after
mkdir -p "$before" "$after" "$output"
dts=arch/arm64/boot/dts/rockchip
files=("$dts/Makefile" "$dts/rk3528-nanopi.dtsi" "$dts/rk3528-nanopi-r28s.dts"
  drivers/bluetooth/hci_uart.h drivers/bluetooth/hci_ldisc.c drivers/bluetooth/Makefile drivers/bluetooth/Kconfig)
for file in "${files[@]}"; do
  if ! upstream_file gregkh/linux "v$release" "$file" "$before/$file"; then
    [[ "$file" == "$dts/"*.dts* ]] || upstream_die "Target kernel file missing: $file"
  fi
  for overlay in "$root/target/linux/generic/files" "$root/target/linux/rockchip/files"; do
    if [[ -f "$overlay/$file" ]]; then mkdir -p "$before/$(dirname "$file")"; cp "$overlay/$file" "$before/$file"; fi
  done
done
# OpenWrt applies generic backports, pending changes, hacks, then target patches.
for queue in "$root/target/linux/generic/backport-$kernel" "$root/target/linux/generic/pending-$kernel" \
  "$root/target/linux/generic/hack-$kernel" "$root/target/linux/rockchip/patches-$kernel"; do
  [[ -d "$queue" ]] || continue
  while IFS= read -r patch; do
    args=()
    matched=0
    for file in "${files[@]}"; do
      args+=("--include=$file")
      if grep -F "$file" "$patch" >/dev/null; then matched=1; fi
    done
    (( matched )) || continue
    git -C "$before" apply --whitespace=nowarn "${args[@]}" "$patch" || upstream_die "Cannot reconstruct target kernel context from $patch"
  done < <(find "$queue" -maxdepth 1 -type f -name '*.patch' | LC_ALL=C sort)
done
cp -R "$before/." "$after/"
cp "$sources/linux/rk3528-nanopi.dtsi" "$after/$dts/"
cp "$sources/linux/rk3528-nanopi-r28s.dts" "$after/$dts/"
if ! grep -q 'rk3528-nanopi-r28s.dtb' "$after/$dts/Makefile"; then
  printf '\ndtb-$(CONFIG_ARCH_ROCKCHIP) += rk3528-nanopi-r28s.dtb\n' >> "$after/$dts/Makefile"
fi
# Reuse the UART Bluetooth node from Armbian's selected board DTS.
awk '
  /^[\t ]*bluetooth \{/ { if (found) exit 1; active=1; found=1 }
  active { print; line=$0; opens=gsub(/\{/, "", line); line=$0; closes=gsub(/\}/, "", line); depth+=opens-closes; if (depth==0) active=0 }
  END { if (!found || active) exit 1 }
' "$sources/vendor-board.dts" > "$work/bluetooth.node" || upstream_die 'Cannot extract the Armbian UART Bluetooth node'
grep -q 'cvte,aic8800-bt' "$work/bluetooth.node" || upstream_die 'Armbian Bluetooth binding changed'
for required in 'gpio-keys {' 'button-user {' '&leds {'; do
  grep -F "$required" "$after/$dts/rk3528-nanopi-r28s.dts" >/dev/null || upstream_die "Upstream board layout changed: $required"
done
cat >> "$after/$dts/rk3528-nanopi-r28s.dts" <<'DTS'

/* OpenWrt status indicators and reset semantics. */
/ {
	aliases {
		led-boot = &rexwrt_sys_led;
		led-failsafe = &rexwrt_sys_led;
		led-running = &rexwrt_sys_led;
		led-upgrade = &rexwrt_sys_led;
	};
	gpio-keys {
		button-user {
			linux,code = <KEY_RESTART>;
		};
	};
};

&leds {
	rexwrt_sys_led: led-0 {
		default-state = "off";
		function = LED_FUNCTION_STATUS;
		linux,default-trigger = "none";
	};
};

&uart2 {
DTS
cat "$work/bluetooth.node" >> "$after/$dts/rk3528-nanopi-r28s.dts"
printf '};\n' >> "$after/$dts/rk3528-nanopi-r28s.dts"

# Port Armbian's UART protocol into the target kernel's existing HCI UART driver.
header=$after/drivers/bluetooth/hci_uart.h
# Inspect the reconstructed API, including OpenWrt backports, rather than guessing
# from the kernel version. H4 reception now takes the UART instead of its HCI device.
h4_arg=$(awk '
  /h4_recv_buf[[:space:]]*\(/ { active=1 }
  active {
    declaration=declaration " " $0
    if (index($0, ";")) {
      if (declaration ~ /h4_recv_buf[[:space:]]*\([[:space:]]*struct hci_uart[[:space:]]*\*/) print "hu"
      else if (declaration ~ /h4_recv_buf[[:space:]]*\([[:space:]]*struct hci_dev[[:space:]]*\*/) print "hu->hdev"
      active=0; declaration=""
    }
  }
' "$header")
[[ "$h4_arg" == hu || "$h4_arg" == 'hu->hdev' ]] || upstream_die 'Unrecognized target h4_recv_buf API'
# OpenWrt retains the source module name, unlike the DKMS installation's suffix.
awk -v argument="$h4_arg" '
  {
    gsub(/request_module\("aic8800_fdrv_sdio"\)/, "request_module(\"aic8800_fdrv\")")
    calls+=gsub(/h4_recv_buf[[:space:]]*\([[:space:]]*hu(->hdev)?[[:space:]]*,/, "h4_recv_buf(" argument ",")
    print
  }
  END { if (calls != 1) exit 1 }
' "$sources/hci_aic.c" > "$after/drivers/bluetooth/hci_aic.c" || upstream_die 'Armbian H4 receive call layout changed'
if ! grep -q '^#define HCI_UART_AIC' "$header"; then
  max=$(awk '$1=="#define" && $2=="HCI_UART_MAX_PROTO" {print $3}' "$header")
  [[ "$max" =~ ^[0-9]+$ ]] || upstream_die 'Cannot allocate an HCI UART protocol ID'
  awk -v id="$max" '
    $1=="#define" && $2=="HCI_UART_MAX_PROTO" { print "#define HCI_UART_MAX_PROTO\t" id+1; print "#define HCI_UART_AIC\t" id; count++; next }
    { print }
    END { if (count != 1) exit 1 }
  ' "$header" > "$work/hci_uart.h"
  mv "$work/hci_uart.h" "$header"
  cat >> "$header" <<'HEADER'

#ifdef CONFIG_BT_HCIUART_AIC
int aic_init(void);
int aic_deinit(void);
#endif
HEADER
fi
ldisc=$after/drivers/bluetooth/hci_ldisc.c
if ! grep -q 'aic_init();' "$ldisc"; then
  awk '
    { print }
    /mrvl_init\(\);/ { init=1 }
    /mrvl_deinit\(\);/ { deinit=1 }
    /^#endif/ && init { print "#ifdef CONFIG_BT_HCIUART_AIC\n\taic_init();\n#endif"; init=0; found_init++ }
    /^#endif/ && deinit { print "#ifdef CONFIG_BT_HCIUART_AIC\n\taic_deinit();\n#endif"; deinit=0; found_deinit++ }
    END { if (found_init != 1 || found_deinit != 1) exit 1 }
  ' "$ldisc" > "$work/hci_ldisc.c" || upstream_die 'HCI UART initialization layout changed'
  mv "$work/hci_ldisc.c" "$ldisc"
fi
if ! grep -q 'CONFIG_BT_HCIUART_AIC' "$after/drivers/bluetooth/Makefile"; then
  printf '\nhci_uart-$(CONFIG_BT_HCIUART_AIC) += hci_aic.o\n' >> "$after/drivers/bluetooth/Makefile"
fi
if ! grep -q '^config BT_HCIUART_AIC$' "$after/drivers/bluetooth/Kconfig"; then
  cat >> "$after/drivers/bluetooth/Kconfig" <<'KCONFIG'

config BT_HCIUART_AIC
	bool "AICSemi UART protocol support"
	depends on BT_HCIUART_SERDEV
	select BT_HCIUART_H4
	help
	  UART Bluetooth support for AICSemi modules with firmware loaded over SDIO.
KCONFIG
fi
status=0
(cd "$work" && git diff --no-index --no-renames --src-prefix= --dst-prefix= before after) > "$output/999-rexwrt-r28s.patch" || status=$?
[[ "$status" == 1 ]] || upstream_die 'Failed to generate R28S kernel diff'
git -C "$before" apply --check "$output/999-rexwrt-r28s.patch"
printf '%s\n' "$kernel" > "$output/kernel-version"
printf '%s\n' "$release" > "$output/kernel-release"
printf 'Generated R28S device and UART Bluetooth patch for Linux %s\n' "$release"
