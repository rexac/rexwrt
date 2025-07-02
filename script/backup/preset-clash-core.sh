#!/bin/bash
#=================================================
# File name: preset-clash-core.sh
# System Required: Linux
# Version: 1.0
# Lisence: MIT
# Author: SuLingGG
# Blog: https://mlapp.cn
#=================================================
preset_clash_core() {
  local architecture=$1
  local CLASH_DEV_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/dev/clash-linux-${architecture}.tar.gz"
  local CLASH_TUN_URL=$(curl -fsSL https://api.github.com/repos/vernesong/OpenClash/contents/master/premium\?ref\=core | grep download_url | grep $architecture | awk -F '"' '{print $4}' | grep -v "v3" )
  local CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-${architecture}.tar.gz"
  local GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
  local GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

  mkdir -p $OPENWRTROOT/files/etc/openclash/core
  pushd $OPENWRTROOT/files/etc/openclash
  wget -qO- $CLASH_DEV_URL | tar xOvz > core/clash
  wget -qO- $CLASH_TUN_URL | gunzip -c > core/clash_tun
  wget -qO- $CLASH_META_URL | tar xOvz > core/clash_meta
  wget -qO- $GEOIP_URL > GeoIP.dat
  wget -qO- $GEOSITE_URL > GeoSite.dat
  chmod +x core/clash*
  popd
}

config_path="$GITHUB_WORKSPACE/config/device/$DEVICE.config.seed"

if grep -q "armv8" $config_path; then
  preset_clash_core arm64
elif grep -q "x86_64" $config_path; then
  preset_clash_core amd64
fi
