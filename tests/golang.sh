#!/usr/bin/env bash
# Verify official Go imports and stable compiler retention without compilation.
set -euo pipefail
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$work/bin" "$work/source/lang/golang/golang"
cat > "$work/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GO_GIT_LOG"
if [[ "$1" == clone ]]; then
  [[ "$*" == *'--branch master https://github.com/openwrt/packages '* ]]
  mkdir -p "${!#}"
  cp -R "$GO_SOURCE_FIXTURE/." "${!#}/"
elif [[ "$3" == sparse-checkout ]]; then
  [[ "$*" == *'sparse-checkout set lang/golang' ]]
elif [[ "$3" == rev-parse ]]; then
  printf '1111111111111111111111111111111111111111\n'
else
  exit 1
fi
MOCK
chmod +x "$work/bin/git"
export PATH="$work/bin:$PATH" GO_SOURCE_FIXTURE=$work/source GO_GIT_LOG=$work/git.log
manifest() { (cd "$1" && find . -type f -exec shasum -a 256 {} + | LC_ALL=C sort); }
for version in 1.27 1.43; do
  incoming=$work/source/lang/golang
  rm -rf "$incoming"
  mkdir -p "$incoming/golang" "$incoming/golang-bootstrap" "$incoming/golang$version"
  printf 'PKG_NAME:=golang\n' > "$incoming/golang/Makefile"
  printf 'PKG_NAME:=golang-bootstrap\n' > "$incoming/golang-bootstrap/Makefile"
  printf 'PKG_NAME:=golang%s\nGO_VERSION_MAJOR_MINOR:=%s\n' "$version" "$version" > "$incoming/golang$version/Makefile"
  for file in golang-package.mk golang-values.mk golang-version.mk; do printf 'official helper\n' > "$incoming/$file"; done
  tree=$work/tree-$version
  mkdir -p "$tree/feeds/packages/lang/golang/golang1.26" "$tree/feeds/packages/net/tailscale" \
    "$tree/package/feeds/packages" "$tree/scripts" "$tree/tmp"
  printf 'PKG_NAME:=golang1.26\n' > "$tree/feeds/packages/lang/golang/golang1.26/Makefile"
  printf 'PKG_BUILD_DEPENDS:=golang%s/host other/host\n' "$version" > "$tree/feeds/packages/net/tailscale/Makefile"
  printf 'stale metadata\n' > "$tree/tmp/.packageinfo"
  printf 'CONFIG_PACKAGE_tailscale=y\n' > "$tree/.config"
  cat > "$tree/scripts/feeds" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GO_FEEDS_LOG"
printf 'refreshed config\n' > "$OPENWRTROOT/.config"
if [[ "$1" == install ]]; then
  [[ "$2" == -p && "$3" == packages ]]
  shift 3
  for name in "$@"; do
    ln -sfn "$OPENWRTROOT/feeds/packages/lang/golang/$name" "$OPENWRTROOT/package/feeds/packages/$name"
  done
fi
MOCK
  chmod +x "$tree/scripts/feeds"
  export OPENWRTROOT=$tree GO_FEEDS_LOG=$work/feeds-$version.log
  bash "$project/scripts/customize/golang.sh" > "$work/log"
  cmp "$incoming/golang$version/Makefile" "$tree/feeds/packages/lang/golang/golang$version/Makefile"
  grep -qx "PKG_BUILD_DEPENDS:=golang$version/host other/host" "$tree/feeds/packages/net/tailscale/Makefile" || fail 'package dependencies rewritten'
  [[ -f "$tree/package/feeds/packages/golang$version/Makefile" ]] || fail 'new host recipe not installed'
  [[ -f "$tree/package/feeds/packages/golang1.26/Makefile" ]] || fail 'older compiler removed'
  [[ ! -e "$tree/tmp/.packageinfo" ]] || fail 'stale package metadata retained'
  grep -qx 'CONFIG_PACKAGE_tailscale=y' "$tree/.config" || fail 'feed refresh changed configuration seeds'
  [[ $(head -1 "$GO_FEEDS_LOG") == 'update -i packages' ]] || fail 'feed index not refreshed first'
  jq -e '.repository == "https://github.com/openwrt/packages" and .branch == "master" and .retained_feed_compilers == ["golang1.26"]' \
    "$tree/.rexwrt/golang-source.json" >/dev/null || fail 'source metadata incorrect'
  cmp "$tree/.rexwrt/golang-source.json" "$tree/files/etc/rexwrt/golang-source.json"

  rm "$incoming/golang-package.mk"
  manifest "$tree" > "$work/before"
  if bash "$project/scripts/customize/golang.sh" > "$work/error" 2>&1; then fail 'incomplete upstream accepted'; fi
  manifest "$tree" > "$work/after"
  cmp "$work/before" "$work/after" || fail 'invalid upstream modified checkout'
done
printf 'PASS: official Go master imports follow versions, retain stable compilers and refresh host links\n'
