#!/usr/bin/env bash
set -euo pipefail

# Update Go from official master while retaining older feed compilers.
update_golang() (
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
  mkdir -p "$OPENWRTROOT/.rexwrt"
  cp "$work/source.json" "$OPENWRTROOT/.rexwrt/golang-source.json"
  printf 'Updated Go from official packages/master at %s; refreshed host package links.\n' "$revision"
)

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0

: "${OPENWRTROOT:?}"
while IFS= read -r -d '' file; do
  sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g;
    s|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' "$file"
done < <(find "$OPENWRTROOT/package" -type f -name Makefile -print0)
sed -i 's/dnsmasq /dnsmasq-full /' "$OPENWRTROOT/include/target.mk"

# Keep the project's custom package updates, but only patch existing recipes.
tailscale=$OPENWRTROOT/feeds/packages/net/tailscale/Makefile
if [[ -f "$tailscale" ]]; then
  version=$(curl -fLSs --retry 3 https://api.github.com/repos/tailscale/tailscale/releases/latest | jq -er '.tag_name | select(test("^v[0-9]")) | ltrimstr("v")')
  digest=$(curl -fLSs --retry 3 "https://github.com/tailscale/tailscale/archive/refs/tags/v${version}.tar.gz" | sha256sum)
  sed -i "/^PKG_VERSION:=/c\\PKG_VERSION:=$version" "$tailscale"
  sed -i "/^PKG_HASH:=/c\\PKG_HASH:=${digest%% *}" "$tailscale"
fi
update_golang
rust=$OPENWRTROOT/feeds/packages/lang/rust/Makefile
if [[ -f "$rust" ]]; then
  sed -i 's/llvm.download-ci-llvm=true/llvm.download-ci-llvm=false/g' "$rust"
  if ! grep -q 'llvm.download-ci-llvm=false' "$rust"; then
    sed -i 's/$(TARGET_CONFIGURE_ARGS)/--set=llvm.download-ci-llvm=false \\\n\t$(TARGET_CONFIGURE_ARGS)/g' "$rust"
  fi
fi
sed -i 's/mkdir \$(PKG_BUILD_DIR)\/\$(ARCH)/mkdir -p \$(PKG_BUILD_DIR)\/\$(ARCH)/g' "$OPENWRTROOT/package/coremark/Makefile"
gpgme=$OPENWRTROOT/feeds/packages/libs/gpgme/Makefile
if [[ -f "$gpgme" ]] && ! grep -q 'find $(PKG_BUILD_DIR).*usr/include' "$gpgme"; then
  sed -i '/\$(eval \$(call BuildPackage,libgpgme))/i\
define Build/Compile\n\
\tfind $(PKG_BUILD_DIR) -type f -name Makefile -exec sed -i "s|-I/usr/include||g" {} +\n\
\t$(call Build/Compile/Default)\n\
endef\n' "$gpgme"
fi
