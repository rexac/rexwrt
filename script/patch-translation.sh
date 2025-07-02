#!/bin/bash
#=================================================
# File name: patch-translation.sh
# System Required: Linux
# Version: 1.0
# Lisence: GPL-3.0
# Author: Rex
# Blog: https://rexe.cc
#=================================================
target_file="$OPENWRTROOT/feeds/luci/modules/luci-base/po/zh_Hans/base.po"

append_translation() {
  echo >> $target_file
  echo "msgid \"$1\"" >> $target_file
  echo "msgstr \"$2\"" >> $target_file
}

# append_translation "Externally managed interface" "外部协议"
# append_translation "Delay" "延迟"
# append_translation "Afer making changes to network using external protocol, network must be manually restarted." "使用外部协议更改网络后，需要重启网络服务。"
# append_translation "Search domain" "查找域"
append_translation "Online Users" "在线用户数"
