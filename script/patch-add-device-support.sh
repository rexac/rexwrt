#!/bin/bash
#=================================================
# File name: patch-add-device-support.sh
# System Required: Linux
# Version: 1.0
# Lisence: GPL-3.0
# Author: Rex
# Blog: https://rexe.cc
#=================================================
execute_sed() {
  local file=$1
  local pattern=$2
  local insert_text=$(cat $3 | sed -e 's#\t#€#g' -e ':a;N;$!ba;s#\n#£#g' -e 's#[]\.|$(){}?+*^]#\\&#g')
  local position=$4
  local delete=${5:-false}
  local single_line_pattern=$(echo "$pattern" | sed -e 's#\\n#£#g' -e 's#\\t#€#g')

  sed -i 's#\t#€#g' $file
  sed -i ':a;N;$!ba;s#\n#£#g' $file

  if grep -q "$single_line_pattern" $file; then
    if [ "$position" = "above" ]; then
      sed -i "s#$single_line_pattern#$insert_text£$single_line_pattern#g" $file
    elif [ "$position" = "below" ]; then
      sed -i "s#$single_line_pattern#$single_line_pattern£$insert_text#g" $file
    elif [ "$position" = "append" ]; then
      sed -i "s#$single_line_pattern#$single_line_pattern$insert_text#g" $file
    fi
    [ "$delete" = "true" ] && sed -i "s#$single_line_pattern##g" $file
  else
    echo "Pattern '$pattern' not found in $file"
    exit 1
  fi

  sed -i 's#£#\n#g' $file
  sed -i 's#€#\t#g' $file
}

if [[ "$BRANCH" == *24.10* ]]; then
  uboot_ver=2024.01
else
  uboot_ver=2025.01
fi
patch_uboot="$GITHUB_WORKSPACE/patch/u-boot/$uboot_ver"
patch_kernel="$GITHUB_WORKSPACE/patch/kernel"
patch_board="$GITHUB_WORKSPACE/patch/board"

if [ "$DEVICE" == "nanopi-neo2-black" ]; then
  cp -r $patch_uboot/* $OPENWRTROOT/package/boot
  cp -r $patch_kernel/* $OPENWRTROOT/target/linux

  sed -i '/^\tnanopi_neo2/ i \\tnanopi_neo2_black \\' $OPENWRTROOT/package/boot/uboot-sunxi/Makefile
  execute_sed "$OPENWRTROOT/package/boot/uboot-sunxi/Makefile" "define U-Boot/nanopi_neo2" "$patch_board/uboot-sunxi_Makefile" "above"
  execute_sed "$OPENWRTROOT/target/linux/sunxi/image/cortexa53.mk" "define Device/friendlyarm_nanopi-neo2" "$patch_board/sunxi_image_cortexa53.mk" "above"
  execute_sed "$OPENWRTROOT/target/linux/sunxi/cortexa53/config-*" "CONFIG_64BIT=y" "$patch_board/sunxi_cortexa53_config" "below"

fi
