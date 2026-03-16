#!/bin/bash
#=================================================
# File name: patch-custom.sh
# System Required: Linux
# Version: 1.0
# Lisence: GPL-3.0
# Author: Rex
# Blog: https://rexe.cc
#=================================================

# Correct path issues
Makefile_path="$({ find $OPENWRTROOT/package -name "Makefile" -not -name "Makefile.*"; } 2> "/dev/null")"

for file in ${Makefile_path}; do
  sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' $file
  sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' $file
done

# Use dnsmasq-full instead of dnsmasq
sed -i 's/dnsmasq /dnsmasq-full /' $OPENWRTROOT/include/target.mk

# Replace the default startup script and configuration of tailscale.
sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' $OPENWRTROOT/feeds/packages/net/tailscale/Makefile

# tailscale: bomp version to latest.
VER=$(curl -sSL https://api.github.com/repos/tailscale/tailscale/releases/latest | jq -r .tag_name | sed 's/v//')
HASH=$(wget -qO- "https://github.com/tailscale/tailscale/archive/refs/tags/v${VER}.tar.gz" | sha256sum | awk '{print $1}')
sed -i "/PKG_VERSION:=/c\PKG_VERSION:=${VER}" $OPENWRTROOT/feeds/packages/net/tailscale/Makefile
sed -i "/PKG_HASH:=/c\PKG_HASH:=${HASH}" $OPENWRTROOT/feeds/packages/net/tailscale/Makefile

# remove the default startup script and configuration of zerotier.
rm -rf $OPENWRTROOT/feeds/packages/net/zerotier/files/etc/init.d $OPENWRTROOT/feeds/packages/net/zerotier/files/etc/config

# golang: bomp version to latest. 
rm -rf $OPENWRTROOT/feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang $OPENWRTROOT/feeds/packages/lang/golang

# rust: disable download-ci-llvm to prevent build error
sed -i 's/llvm.download-ci-llvm=true/llvm.download-ci-llvm=false/g' $OPENWRTROOT/feeds/packages/lang/rust/Makefile
if ! grep -q "llvm.download-ci-llvm=false" $OPENWRTROOT/feeds/packages/lang/rust/Makefile; then
  sed -i 's/$(TARGET_CONFIGURE_ARGS)/--set=llvm.download-ci-llvm=false \\\n\t$(TARGET_CONFIGURE_ARGS)/g' $OPENWRTROOT/feeds/packages/lang/rust/Makefile
fi

# gpgme: disable fortify-source to prevent musl and gcc-14 fortify header conflicts
sed -i '/TARGET_CFLAGS += -D_LARGEFILE64_SOURCE/a\  TARGET_CFLAGS += -U_FORTIFY_SOURCE' $OPENWRTROOT/feeds/packages/libs/gpgme/Makefile
