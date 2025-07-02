#!/bin/bash
#=================================================
# File name: update-clang-alternatives.sh
# System Required: Linux
# Version: 1.0
# Lisence: GPL-3.0
# Author: Rex
# Blog: https://rexe.cc
#=================================================

ver="15"
[[ $BRANCH == *23.05* ]] && ver="13"

sudo -E apt-get install -y clang-$ver

BINARIES=($(ls /usr/bin | grep -E "(clang|llvm).*${ver}"))

for bin in "${BINARIES[@]}"; do
  if [ -f "/usr/bin/$bin" ]; then
    sudo -E update-alternatives --install "/usr/bin/${bin//-$ver}" "${bin//-$ver}" "/usr/bin/$bin" 100
  else
    echo "Binary /usr/bin/$bin does not exist."
  fi
done
