#!/bin/bash
#=================================================
# File name: external-toolchain.sh
# System Required: Linux
# Version: 1.0
# Lisence: GPL-3.0
# Author: Rex
# Blog: https://rexe.cc
#=================================================

dl_toolchain() {
  local TARGET_NAME=$1
  local url="https://downloads.cdn.openwrt.org/$( [[ "${BRANCH}" == "main" ]] && echo "snapshots" || echo "releases/${BRANCH#v}" )/targets/$TARGET_NAME/"
  local html=$(curl -s $url)
  local toolchain_file=$(echo "$html" | grep -o '<a href="openwrt-toolchain[^"]*' | awk -F'"' '{ print $2 }')
  local toolchain_url="$url$toolchain_file"

  wget $toolchain_url
  mkdir external-toolchain
  tar -xf $toolchain_file --strip-components=1 -C external-toolchain
  rm $toolchain_file
 
  local folder=$(find external-toolchain -maxdepth 1 -type d -name "toolchain*" -print -quit)
  local TOOLCHAIN=$(readlink -f $folder)

  $OPENWRTROOT/scripts/ext-toolchain.sh \
    --toolchain $TOOLCHAIN \
    --overwrite-config \
    --config $TARGET_NAME
}

config_path="$GITHUB_WORKSPACE/config/device/$DEVICE.config.seed"
Architecture=$(grep -o 'TARGET_[[:alnum:]]*=y' $config_path | awk -F'[_=]' '{print $2}')
Subtarget=$(grep -o "${Architecture}_[[:alnum:]]*=y" $config_path | awk -F'[_=]' '{print $2}')
  
dl_toolchain "$Architecture/$Subtarget"

# Prepared for simplifying images name.
[[ $Architecture == *"x86"* ]] && TARGET_NAME='' || TARGET_NAME=-$Architecture-$Subtarget
echo "TARGET_NAME=$TARGET_NAME" >> $GITHUB_ENV
