#!/usr/bin/env bash
set -euo pipefail
device_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${OPENWRTROOT:-}
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --openwrt-root=*) root=${arg#*=} ;;
    --dry-run) dry_run=1 ;;
    *) echo "Unsupported NEO2 Black option: $arg" >&2; exit 1 ;;
  esac
done
[[ -d "$root/target/linux/sunxi" ]] || { echo 'Sunxi source tree required' >&2; exit 1; }
root=$(cd "$root" && pwd)
if grep -q '^define Device/friendlyarm_nanopi-neo2-black$' "$root/target/linux/sunxi/image/cortexa53.mk"; then
  echo 'NEO2 Black support already exists'
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export PATCH_OUTPUT_DIR=$work/generated
if (( dry_run )); then
  bash "$device_dir/fetch-patches.sh" --openwrt-root="$root" --dry-run
  bash "$device_dir/generate-cpuinfo-patch.sh" "$root" "$PATCH_OUTPUT_DIR/kernel" 1
  exit 0
fi
bash "$device_dir/fetch-patches.sh" --openwrt-root="$root"
bash "$device_dir/generate-cpuinfo-patch.sh" "$root" "$PATCH_OUTPUT_DIR/kernel"
cp -R "$PATCH_OUTPUT_DIR/kernel/." "$root/target/linux/"
cp -R "$PATCH_OUTPUT_DIR/u-boot/." "$root/package/boot/"

insert_before() {
  local file=$1 anchor=$2 fragment=$3
  ANCHOR="$anchor" awk -v fragment="$fragment" '
    $0 == ENVIRON["ANCHOR"] { while ((getline line < fragment) > 0) print line; close(fragment); count++ }
    { print }
    END { if (count != 1) exit 1 }
  ' "$file" > "$work/inserted"
  cat "$work/inserted" > "$file"
}
boot=$root/package/boot/uboot-sunxi/Makefile
insert_before "$boot" 'define U-Boot/nanopi_neo2' "$device_dir/patches/board/uboot-sunxi_Makefile"
printf '\tnanopi_neo2_black \\\n' > "$work/target-list"
insert_before "$boot" $'\tnanopi_neo2 \\' "$work/target-list"
insert_before "$root/target/linux/sunxi/image/cortexa53.mk" \
  'define Device/friendlyarm_nanopi-neo2' "$device_dir/patches/board/sunxi_image_cortexa53.mk"
for config in "$root"/target/linux/sunxi/cortexa53/config-*; do
  printf '\n' >> "$config"
  cat "$device_dir/patches/board/sunxi_cortexa53_config" >> "$config"
done
for config in "$root"/target/linux/sunxi/config-*; do
  sed -i 's/^CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/# CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE is not set/;
    /^# CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL is not set/d;
    s/^# CONFIG_PINCTRL_SUN8I_H3 is not set/CONFIG_PINCTRL_SUN8I_H3=y/;
    s/^# CONFIG_PINCTRL_SUN8I_H3_R is not set/CONFIG_PINCTRL_SUN8I_H3_R=y/' "$config"
  printf '\nCONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y\n' >> "$config"
done
