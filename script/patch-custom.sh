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

# tailscale: bomp version to 1.84.2.
sed -i "/PKG_VERSION:=/c\PKG_VERSION:=1.84.2" $OPENWRTROOT/feeds/packages/net/tailscale/Makefile
sed -i "/PKG_HASH:=/c\PKG_HASH:=32673e5552e1176f1028a6a90a4c892d2475c92d1e952ca16156dc523d14d914" $OPENWRTROOT/feeds/packages/net/tailscale/Makefile

# remove the default startup script and configuration of zerotier.
rm -rf $OPENWRTROOT/feeds/packages/net/zerotier/files/etc/init.d $OPENWRTROOT/feeds/packages/net/zerotier/files/etc/config

# golang: bomp version to latest. 
rm -rf $OPENWRTROOT/feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang $OPENWRTROOT/feeds/packages/lang/golang
