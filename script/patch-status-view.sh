#!/bin/bash
#=================================================
# File name: patch-status-view.sh
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

insert_path="$GITHUB_WORKSPACE/patch/status-view"
file_a="$OPENWRTROOT/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
file_b="$OPENWRTROOT/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
file_c="$OPENWRTROOT/feeds/luci/modules/luci-mod-status/root/usr/share/rpcd/acl.d/luci-mod-status.json"
file_d="$OPENWRTROOT/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/30_network.js"

execute_sed $file_a "\t}\n};\n\n" "$insert_path/ucode-luci" "above"

execute_sed $file_b "method: 'info'\n});" "$insert_path/system-a.js" "below"
execute_sed $file_b "L.resolveDefault(callSystemInfo(), {})," "$insert_path/system-b.js" "below"
execute_sed $file_b "\n\t\t    luciversion = data\[2\];" "$insert_path/system-c.js" "below" "true"
execute_sed $file_b "\n\t\t\t_('Model'),            boardinfo.model,\n\t\t\t_('Architecture'),     boardinfo.system," "$insert_path/system-d.js" "below" "true"
execute_sed $file_b "\t\t\t) : null" "$insert_path/system-e.js" "append"
execute_sed $file_b "\t\t];" "$insert_path/system-f.js" "below"

execute_sed $file_c '\n\t\t\t\t"luci": \[ "getConntrackList", "getRealtimeStats" \],' "$insert_path/luci-mod-status.json" "below" "true"

execute_sed $file_d "'require network';" "$insert_path/network-a.js" "below"
execute_sed $file_d "network.getWAN6Networks()" "$insert_path/network-b.js" "append"
execute_sed $file_d "wan6_nets = data\[3\]" "$insert_path/network-c.js" "append"
execute_sed $file_d "_('Active Connections'), ct_max ? ct_count : null" "$insert_path/network-d.js" "append"
execute_sed $file_d "\n\t\t\tctstatus.appendChild(E('tr', { 'class': 'tr' }, \[\n\t\t\t\tE('td', { 'class': 'td left', 'width': '33%' }, \[ fields\[i\] \]),\n\t\t\t\tE('td', { 'class': 'td left' }, \[\n\t\t\t\t\t(fields\[i + 1\] != null) ? progressbar(fields\[i + 1\], ct_max) : '?'\n\t\t\t\t\])\n\t\t\t\]));" "$insert_path/network-e.js" "below" "true"
