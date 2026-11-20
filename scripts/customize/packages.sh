#!/usr/bin/env bash
set -euo pipefail
: "${OPENWRTROOT:?}" "${REXWRT_ROOT:?}" "${DEVICE:?}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$OPENWRTROOT/package"

clone_and_extract() {
  local repo=$1 path=$2 branch=${3:-} target
  target=$(basename "$path")
  local args=(--depth 1 --filter=blob:none --sparse)
  [[ -z "$branch" ]] || args+=(--branch "$branch")
  git clone "${args[@]}" "$repo" "$work/repository"
  git -C "$work/repository" sparse-checkout set "$path"
  if [[ ! -f "$work/repository/$path/Makefile" ]]; then
    printf 'Missing package recipe: %s at %s (%s)\n' "$path" "$repo" "${branch:-default branch}" >&2
    exit 1
  fi
  mkdir -p "$target"
  cp -R "$work/repository/$path/." "$target/"
  rm -rf "$work/repository"
}

rm -rf "$OPENWRTROOT"/feeds/luci/applications/{luci-app-argon-config,luci-app-cpufreq,luci-app-diskman,luci-app-mosdns,luci-app-openclash}
rm -rf "$OPENWRTROOT/feeds/luci/themes/luci-theme-argon" "$OPENWRTROOT/feeds/packages/utils/coremark"
if [[ "$TARGET_BOARD" != x86 ]]; then git clone --depth 1 https://github.com/sbwml/autocore-arm; fi
clone_and_extract https://github.com/coolsnowwolf/packages utils/coremark
clone_and_extract https://github.com/immortalwrt/luci applications/luci-app-cpufreq
clone_and_extract https://github.com/immortalwrt/immortalwrt package/emortal/cpufreq
if [[ "$DEVICE" == nanopi-neo2-black ]]; then
  sed -i '/allwinner,sun50i-h6")/i\\t\t"allwinner,sun50i-h5")\n\t\t\tuci_write_config 0 schedutil "$CPU_MIN_FREQ" "$CPU_MAX_FREQ"\n\t\t\t;;' cpufreq/files/cpufreq.uci
fi
mkdir -p parted
curl -fLSs --retry 3 https://raw.githubusercontent.com/lisaac/luci-app-diskman/master/Parted.Makefile -o parted/Makefile
clone_and_extract https://github.com/lisaac/luci-app-diskman applications/luci-app-diskman
if [[ ! -d "$OPENWRTROOT/feeds/luci/applications/luci-app-irqbalance" ]]; then
  clone_and_extract https://github.com/openwrt/luci applications/luci-app-irqbalance
fi
# Remove duplicate feed recipes before supplying the customized MosDNS sources.
if [[ "$DEVICE" != nanopi-r28s ]]; then
find "$OPENWRTROOT/feeds" -type f -name Makefile \( -path '*/v2ray-geodata/*' -o -path '*/mosdns/*' \) -delete
git clone --depth 1 --branch v5 https://github.com/sbwml/luci-app-mosdns mosdns
git clone --depth 1 https://github.com/sbwml/v2ray-geodata
if [[ ! -d "$OPENWRTROOT/feeds/luci/applications/luci-app-openlist" ]]; then
  clone_and_extract https://github.com/openwrt/packages net/openlist
  clone_and_extract https://github.com/openwrt/luci applications/luci-app-openlist
fi
git clone --depth 1 https://github.com/Zerogiven-OpenWRT-Packages/luci-app-podman
fi
if [[ ! -d "$OPENWRTROOT/feeds/luci/applications/luci-app-zerotier" ]]; then
  rm -rf "$OPENWRTROOT/feeds/packages/net/zerotier"
  clone_and_extract https://github.com/immortalwrt/packages net/zerotier
  clone_and_extract https://github.com/immortalwrt/luci applications/luci-app-zerotier
fi
clone_and_extract https://github.com/immortalwrt/luci themes/luci-theme-argon
if [[ ! -d "$OPENWRTROOT/feeds/luci/applications/luci-app-nikki" ]]; then
  for path in mihomo-alpha mihomo-meta nikki luci-app-nikki; do
    clone_and_extract https://github.com/nikkinikki-org/OpenWrt-nikki "$path"
  done
fi
if [[ -f "$DEVICE_DIR/packages.sh" ]]; then bash "$DEVICE_DIR/packages.sh"; fi
