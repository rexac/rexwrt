#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_device
version=$BRANCH
[[ "$BRANCH" != main ]] || version=snapshot
version=${version//\//-}
release=${RELEASE_DIR:-$REXWRT_ROOT/release/$DEVICE/$version}
mkdir -p "$release"
checksum_file=$release/$version-$DEVICE-sha256sum.txt
shopt -s nullglob
images=("$OPENWRTROOT"/bin/targets/"$TARGET_BOARD"/"$TARGET_SUBTARGET"/*.img.gz)
(( ${#images[@]} )) || die 'No firmware images were generated'
: > "$checksum_file"
for image in "${images[@]}"; do
  name=$(basename "$image")
  name=${name/openwrt-/openwrt-$version-}
  name=${name/-$TARGET_BOARD-$TARGET_SUBTARGET/}
  for suffix in -combined -generic -sysupgrade; do name=${name/$suffix/}; done
  cp "$image" "$release/$name"
  digest=$(sha256sum "$release/$name")
  printf '%s  %s\n' "${digest%% *}" "$name" >> "$checksum_file"
done
if [[ -f "$OPENWRTROOT/.rexwrt/r28s/sources.json" ]]; then
  for name in sources.json sources.tsv kernel-release inputs.sha256; do
    cp "$OPENWRTROOT/.rexwrt/r28s/$name" "$release/r28s-$name"
  done
fi
log "Firmware collected in $release"
if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'FIRMWARE=%s\n' "$release" >> "$GITHUB_ENV"; fi
