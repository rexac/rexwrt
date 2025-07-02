#!/bin/bash
#=================================================
# File name: patch-kernel.sh
# System Required: Linux
# Version: 1.0
# Lisence: GPL-3.0
# Author: Rex
# Blog: https://rexe.cc
#=================================================
patch_path="$GITHUB_WORKSPACE/patch/kernel"

if [ "$DEVICE" == "nanopi-r4s" ]; then
  for dir in $OPENWRTROOT/target/linux/{rockchip/patches*,generic/hack*}/; do
    if [[ $dir == *"rockchip"* ]]; then
      cp -r $patch_path/rockchip/*.patch $dir
    elif [[ $dir == *"generic"* ]]; then
      cp -r $patch_path/generic/*.patch $dir
    fi
  done
fi
