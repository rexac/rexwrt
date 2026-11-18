#!/usr/bin/env bash
set -euo pipefail
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
rm -rf "$OPENWRTROOT/feeds/packages/lang/golang"
git clone --depth 1 https://github.com/sbwml/packages_lang_golang "$OPENWRTROOT/feeds/packages/lang/golang"
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
