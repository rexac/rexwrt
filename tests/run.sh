#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

while IFS= read -r -d '' file; do bash -n "$file"; done < <(
  find "$root/scripts" "$root/devices" "$root/tools" "$root/ci" "$root/tests" -name '*.sh' -type f -print0
)
bash -n "$root/rexwrt"
sh -n "$root/overlay/etc/uci-defaults/99-init-settings"
sh -n "$root/overlay/etc/ppp/ip-down.d/check_wan6_down"
pass 'active shell scripts parse'

expected=$'nanopi-neo2-black\nnanopi-r28s\nx86-64'
[[ $("$root/rexwrt" devices) == "$expected" ]] || fail 'device discovery'
for pair in nanopi-neo2-black:sunxi/cortexa53 nanopi-r28s:rockchip/armv8 x86-64:x86/64; do
  device=${pair%%:*}; target=${pair#*:}
  "$root/rexwrt" plan --device "$device" --branch v25.12.6 > "$work/plan"
  grep -Fx "Target: $target" "$work/plan" >/dev/null || fail "$device target"
done
pass 'device discovery and target resolution'
if "$root/rexwrt" plan --device ../../outside > "$work/error" 2>&1; then fail 'unsafe device accepted'; fi
if "$root/rexwrt" plan --branch ../../outside > "$work/error" 2>&1; then fail 'unsafe branch accepted'; fi
if "$root/rexwrt" plan --jobs 0 > "$work/error" 2>&1; then fail 'zero jobs accepted'; fi
if "$root/rexwrt" invalid > "$work/error" 2>&1; then fail 'unknown command accepted'; fi
pass 'invalid inputs fail before build actions'

# Upstream-supported targets must not invoke another device's adaptation.
source_tree=$work/source
mkdir -p "$source_tree/include" "$source_tree/target/linux/rockchip/image"
: > "$source_tree/include/toplevel.mk"
printf 'define Device/friendlyarm_nanopi-r28s\n' > "$source_tree/target/linux/rockchip/image/armv8.mk"
"$root/rexwrt" adapt --device x86-64 --source "$source_tree" > "$work/adapt"
pass 'device adapters stay isolated'

# Missing prerequisites must fail without creating a partial board profile.
mkdir -p "$source_tree/package/boot/uboot-rockchip"
printf 'KERNEL_PATCHVER:=6.12\n' > "$source_tree/target/linux/rockchip/Makefile"
printf 'PKG_VERSION:=2025.10\n' > "$source_tree/package/boot/uboot-rockchip/Makefile"
if "$root/rexwrt" adapt --device nanopi-r28s --source "$source_tree" > "$work/error" 2>&1; then
  fail 'missing R28S prerequisites accepted'
fi
grep -q 'Missing R28S prerequisite' "$work/error" || fail 'missing prerequisite diagnostic'
pass 'incomplete stable targets rejected before modification'

# Artifact collection must stay within the requested target and leave source images intact.
mkdir -p "$source_tree/bin/targets/rockchip/armv8" "$source_tree/bin/targets/sunxi/cortexa53" "$work/bin"
printf 'firmware\n' > "$source_tree/bin/targets/rockchip/armv8/openwrt-rockchip-armv8-friendlyarm_nanopi-r28s-ext4-sysupgrade.img.gz"
printf 'other device\n' > "$source_tree/bin/targets/sunxi/cortexa53/openwrt-other.img.gz"
# macOS supplies shasum instead of sha256sum.
if ! command -v sha256sum >/dev/null 2>&1; then
  printf '#!/bin/sh\nexec shasum -a 256 "$@"\n' > "$work/bin/sha256sum"
  chmod +x "$work/bin/sha256sum"
fi
DEVICE=nanopi-r28s BRANCH=v25.12.6 OPENWRTROOT="$source_tree" RELEASE_DIR="$work/release" \
  PATH="$work/bin:$PATH" bash "$root/scripts/collect-images.sh" > "$work/images"
[[ -f "$work/release/openwrt-v25.12.6-friendlyarm_nanopi-r28s-ext4.img.gz" ]] || fail 'artifact naming'
[[ ! -f "$work/release/openwrt-other.img.gz" ]] || fail 'collected another target'
[[ -f "$source_tree/bin/targets/rockchip/armv8/openwrt-rockchip-armv8-friendlyarm_nanopi-r28s-ext4-sysupgrade.img.gz" ]] || fail 'source artifact removed'
PATH="$work/bin:$PATH" sh -c 'cd "$1" && sha256sum --check v25.12.6-nanopi-r28s-sha256sum.txt' sh "$work/release"
pass 'target-specific artifacts and valid checksums'

# Stop on the failing build stage; do not create an index or install images.
cat > "$work/bin/uname" <<'MOCK'
#!/bin/sh
printf 'Linux\n'
MOCK
cat > "$work/bin/make" <<'MOCK'
#!/bin/sh
printf '%s\n' "$1" >> "$MAKE_LOG"
[ "$1" != target/compile ]
MOCK
chmod +x "$work/bin/uname" "$work/bin/make"
if MAKE_LOG="$work/make.log" PATH="$work/bin:$PATH" "$root/rexwrt" compile \
  --device nanopi-r28s --source "$source_tree" > "$work/error" 2>&1; then
  fail 'build stage failure ignored'
fi
[[ $(cat "$work/make.log") == $'tools/compile\ntoolchain/compile\ntarget/compile' ]] || fail 'stages continued after failure'
pass 'build stage failures propagate and stop subsequent work'

# An environment-only V is ignored by OpenWrt; retry commands must pass V=s.
cat > "$work/bin/make" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$MAKE_LOG"
if [ "${1}" = target/compile ] || [ "${1}" = target/install ]; then exit 1; fi
MOCK
for stage in compile images; do
  : > "$work/verbose.log"
  if V=s MAKE_LOG="$work/verbose.log" PATH="$work/bin:$PATH" "$root/rexwrt" "$stage" \
    --device nanopi-r28s --source "$source_tree" --jobs 1 > "$work/error" 2>&1; then
    fail "verbose $stage failure ignored"
  fi
  while IFS= read -r invocation; do
    [[ "$invocation" == *' -j1 V=s' ]] || fail "missing command-line verbosity: $invocation"
  done < "$work/verbose.log"
  if [[ "$stage" == images ]]; then
    [[ $(cat "$work/verbose.log") == $'package/install -j1 V=s\ntarget/install -j1 V=s' ]] || fail 'image retry did not reach target installation'
  fi
done
pass 'serial retries pass command-line verbosity and propagate build failures'

# Device compilation must fail before the unrelated full package set starts.
cat > "$work/bin/make" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$MAKE_LOG"
if [ "$1" = "${FAIL_TARGET:-}" ]; then exit 42; fi
MOCK
for branch in main v25.12.6; do
  : > "$work/preflight.log"
  if MAKE_LOG="$work/preflight.log" FAIL_TARGET=package/kernel/aic8800-sdio/compile PATH="$work/bin:$PATH" \
    "$root/rexwrt" preflight --device nanopi-r28s --branch "$branch" --source "$source_tree" --jobs 2 > "$work/error" 2>&1; then
    fail 'device preflight failure ignored'
  fi
  expected=$'tools/compile -j2 V=s\ntoolchain/compile -j2 V=s\ntarget/compile -j2 V=s\npackage/kernel/aic8800-sdio/compile -j2 V=s'
  [[ $(cat "$work/preflight.log") == "$expected" ]] || fail 'preflight compiled unrelated packages or hid diagnostics'
done
for device in nanopi-r28s x86-64; do
  for stage in preflight compile; do
    : > "$work/order.log"
    MAKE_LOG="$work/order.log" PATH="$work/bin:$PATH" "$root/rexwrt" "$stage" \
      --device "$device" --source "$source_tree" > "$work/error" 2>&1
    awk '{print $1}' "$work/order.log" > "$work/targets"
    expected=$'tools/compile\ntoolchain/compile\ntarget/compile'
    if [[ "$device" == nanopi-r28s ]]; then
      expected+=$'\npackage/kernel/aic8800-sdio/compile\npackage/boot/uboot-rexwrt-r28s/compile'
    fi
    if [[ "$stage" == compile ]]; then expected+=$'\npackage/compile\npackage/index\ndiffconfig'; fi
    [[ $(cat "$work/targets") == "$expected" ]] || fail "$device $stage target order or isolation"
  done
done
pass 'device preflight fails early with verbose logs; full builds check devices before other packages'

# NEO2 Black selects Armbian sources from detected versions, not fixed patches.
neo_tree=$work/neo
mkdir -p "$neo_tree/include" "$neo_tree/target/linux/sunxi/image" "$neo_tree/package/boot/uboot-sunxi"
: > "$neo_tree/include/toplevel.mk"
: > "$neo_tree/target/linux/sunxi/image/cortexa53.mk"
cat > "$work/bin/curl" <<'MOCK'
#!/bin/sh
printf 'unexpected network access\n' >> "$CURL_LOG"
exit 1
MOCK
chmod +x "$work/bin/curl"
for versions in 6.6:2024.01 6.12:2025.10 6.18:2026.10; do
  kernel=${versions%:*}; boot=${versions#*:}
  printf 'KERNEL_PATCHVER:=%s\n' "$kernel" > "$neo_tree/target/linux/sunxi/Makefile"
  printf 'PKG_VERSION:=%s\n' "$boot" > "$neo_tree/package/boot/uboot-sunxi/Makefile"
  CURL_LOG="$work/curl.log" PATH="$work/bin:$PATH" "$root/rexwrt" adapt \
    --device nanopi-neo2-black --source "$neo_tree" --dry-run > "$work/neo-plan"
  grep -F "archive/sunxi-$kernel/" "$work/neo-plan" >/dev/null || fail 'NEO2 kernel version selection'
  grep -F "U-Boot version: $boot" "$work/neo-plan" >/dev/null || fail 'NEO2 U-Boot version detection'
  [[ ! -s "$neo_tree/target/linux/sunxi/image/cortexa53.mk" ]] || fail 'NEO2 dry run changed profile'
  [[ ! -d "$neo_tree/target/linux/sunxi/patches-$kernel" ]] || fail 'NEO2 dry run installed patches'
done
[[ ! -e "$work/curl.log" ]] || fail 'NEO2 dry run accessed network'
pass 'NEO2 Black dynamically selects kernel and U-Boot versions without dry-run writes'

bash "$root/tests/neo2.sh"
bash "$root/tests/r28s.sh"
bash "$root/tests/build.sh"
