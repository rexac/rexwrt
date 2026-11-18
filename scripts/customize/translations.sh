#!/usr/bin/env bash
set -euo pipefail
target=$OPENWRTROOT/feeds/luci/modules/luci-base/po/zh_Hans/base.po
if ! grep -q '^msgid "Online Users"$' "$target"; then
  printf '\nmsgid "Online Users"\nmsgstr "在线用户数"\n' >> "$target"
fi
