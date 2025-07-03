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
  cp -r $patch_path/* $OPENWRTROOT/target/linux
fi
