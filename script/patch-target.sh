#!/bin/bash
#=================================================
# File name: patch-target.sh
# System Required: Linux
# Version: 1.0
# Lisence: GPL-3.0
# Author: Rex
# Blog: https://rexe.cc
#=================================================
file="$OPENWRTROOT/include/target.mk"

#if [ "$DEVICE" == "nanopi-r4s" ]; then
#  sed -i "s#CPU_CFLAGS = -Os -pipe#CPU_CFLAGS = -O3 -pipe#g" $file
#  sed -i "s#CPU_CFLAGS_generic = -mcpu=generic#CPU_CFLAGS_generic = -march=armv8-a+crypto+crc -mcpu=cortex-a72.cortex-a53+crypto+crc -mtune=cortex-a72.cortex-a53#g" $file
#fi
