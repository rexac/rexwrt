#!/usr/bin/env bash
# Update only Go from official master; retain older versioned feed compilers.
set -euo pipefail
: "${OPENWRTROOT:?}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repository=https://github.com/openwrt/packages
git clone --depth 1 --filter=blob:none --sparse --branch master "$repository" "$work/source"
git -C "$work/source" sparse-checkout set lang/golang
revision=$(git -C "$work/source" rev-parse HEAD)
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid official Go source revision.' >&2; exit 1; }
incoming=$work/source/lang/golang
current=$OPENWRTROOT/feeds/packages/lang/golang
for file in golang/Makefile golang-package.mk golang-values.mk golang-version.mk; do
  [[ -s "$incoming/$file" ]] || { printf 'Missing official Go source: %s\n' "$file" >&2; exit 1; }
done
: > "$work/retained"
for directory in "$current"/golang[0-9]*; do
  name=${directory##*/}
  if [[ "$name" =~ ^golang[0-9]+\.[0-9]+$ && -f "$directory/Makefile" && ! -e "$incoming/$name" ]]; then
    cp -R "$directory" "$incoming/$name"
    printf '%s\n' "$name" >> "$work/retained"
  fi
done
packages=()
for recipe in "$incoming"/*/Makefile; do
  name=$(sed -nE 's/^PKG_NAME[[:space:]]*:=[[:space:]]*([a-zA-Z0-9_.+-]+)[[:space:]]*$/\1/p' "$recipe")
  [[ -n "$name" && "$name" == "$(basename "$(dirname "$recipe")")" ]] || {
    printf 'Unrecognized official Go package name: %s\n' "$recipe" >&2
    exit 1
  }
  packages+=("$name")
done
(( ${#packages[@]} > 0 )) || { echo 'No official Go packages discovered.' >&2; exit 1; }
jq -Rn '[inputs | select(length > 0)]' < "$work/retained" > "$work/retained.json"
jq -n --arg repository "$repository" --arg revision "$revision" --slurpfile retained "$work/retained.json" \
  '{repository:$repository, branch:"master", commit:$revision, retained_feed_compilers:$retained[0]}' > "$work/source.json"

if [[ -e "$current" ]]; then mv "$current" "$work/previous"; fi
mv "$incoming" "$current"
(
  cd "$OPENWRTROOT"
  # Feed commands refresh .config; preserve seeds until final configuration.
  if [[ -f .config ]]; then
    cp .config "$work/config"
    trap 'cp "$work/config" "$OPENWRTROOT/.config"' EXIT
  fi
  ./scripts/feeds update -i packages
  ./scripts/feeds install -p packages "${packages[@]}"
)
for name in "${packages[@]}"; do
  [[ -f "$OPENWRTROOT/package/feeds/packages/$name/Makefile" ]] || {
    printf 'Official Go package was not installed: %s\n' "$name" >&2
    exit 1
  }
done
rm -f "$OPENWRTROOT/tmp/.packageinfo" "$OPENWRTROOT/tmp/.packagedeps"
mkdir -p "$OPENWRTROOT/.rexwrt" "$OPENWRTROOT/files/etc/rexwrt"
cp "$work/source.json" "$OPENWRTROOT/.rexwrt/golang-source.json"
cp "$work/source.json" "$OPENWRTROOT/files/etc/rexwrt/golang-source.json"
printf 'Updated Go from official packages/master at %s; refreshed host package links.\n' "$revision"
