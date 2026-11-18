#!/usr/bin/env bash
# Missing optional patches should use DTS; server errors must stop adaptation.
set -euo pipefail
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$work/bin" "$work/tree/target/linux/sunxi" "$work/tree/package/boot/uboot-sunxi"
printf 'KERNEL_PATCHVER:=6.18\n' > "$work/tree/target/linux/sunxi/Makefile"
printf 'PKG_VERSION:=2026.04\n' > "$work/tree/package/boot/uboot-sunxi/Makefile"
cat > "$work/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
url= output= status=0
while (( $# )); do
  case "$1" in
    https://*) url=$1 ;;
    -o) output=$2; shift ;;
    -w) status=1; shift ;;
  esac
  shift
done
[[ -n "$url" && -n "$output" ]]
case "$url" in
  */patches.armbian/*.patch)
    : > "$output"
    [[ $status == 1 ]]
    printf '%s' "${NEO_PATCH_STATUS:-404}"
    ;;
  */dt_64/*.dts)
    printf '/dts-v1/;\n#include "sun50i-h5.dtsi"\n/ { model = "FriendlyARM NanoPi NEO Core2"; };\n' > "$output"
    ;;
  */Makefile)
    printf 'dtb-$(CONFIG_ARCH_SUNXI) += sun50i-h5-nanopi-neo2.dtb\n' > "$output"
    ;;
  */sun50i-h5-cpu-opp.dtsi)
    printf '/ {\n\topp-1152000000 {\n\t};\n};\n' > "$output"
    ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH" OPENWRTROOT=$work/tree PATCH_OUTPUT_DIR=$work/output
bash "$project/devices/nanopi-neo2-black/fetch-patches.sh" --kernel-only > "$work/log" 2> "$work/errors"
[[ ! -s "$work/errors" ]] || fail 'expected 404 emitted an error'
grep -q 'No standalone Armbian patch (HTTP 404)' "$work/log" || fail 'DTS fallback unexplained'
patch=$PATCH_OUTPUT_DIR/kernel/sunxi/patches-6.18/001-arm64-dts-Add-sun50i-h5-nanopi-neo2-black-device.patch
[[ -s "$patch" ]] || fail 'DTS fallback did not generate patch'
git apply --stat "$patch" >/dev/null
if NEO_PATCH_STATUS=503 PATCH_OUTPUT_DIR="$work/failed" \
  bash "$project/devices/nanopi-neo2-black/fetch-patches.sh" --kernel-only > "$work/log" 2> "$work/errors"; then
  fail 'server error accepted'
fi
grep -q 'HTTP 503' "$work/errors" || fail 'server error not diagnosed'
if grep -q 'generating it from the board DTS' "$work/log"; then fail 'server error selected fallback'; fi
printf 'PASS: NEO2 optional patch 404 uses DTS; server errors stop adaptation\n'
