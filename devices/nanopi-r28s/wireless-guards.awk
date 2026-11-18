# Use the wireless backport version only for guards controlling wireless APIs.
# Timer, VFS, procfs and other core-kernel guards retain LINUX_VERSION_CODE.
function wireless(text) {
    return text ~ /(cfg80211|nl80211|wiphy|wireless_dev|ieee80211|link_id|radio_idx)/
}
{
    lines[NR]=$0
    if ($0 ~ /^[[:space:]]*#[[:space:]]*if(n?def)?([[:space:]]|\()/) {
        depth++
        start[depth]=NR
    }
    if ($0 ~ /^[[:space:]]*#[[:space:]]*endif/) {
        first=start[depth]
        # Nested wireless branches also determine their enclosing API guard.
        text=""
        for (i=first+1; i<NR; i++) text=text "\n" lines[i]
        # Some optional callback arguments name only net_device; inspect the
        # immediately preceding signature, without classifying its whole body.
        signature=""
        if (text ~ /struct net_device[[:space:]]*\*/) {
            for (i=first-1; i>0 && i>=first-5; i--) {
                if (lines[i] ~ /[{};]/) break
                signature=lines[i] "\n" signature
            }
        }
        if (wireless(text) || wireless(signature)) {
            gsub(/LINUX_VERSION_CODE/, "CFG80211_VERSION", lines[first])
            nested=0
            for (i=first+1; i<NR; i++) {
                if (lines[i] ~ /^[[:space:]]*#[[:space:]]*if(n?def)?([[:space:]]|\()/) nested++
                if (!nested && lines[i] ~ /^[[:space:]]*#[[:space:]]*elif/) gsub(/LINUX_VERSION_CODE/, "CFG80211_VERSION", lines[i])
                if (lines[i] ~ /^[[:space:]]*#[[:space:]]*endif/) nested--
            }
        }
        depth--
        if (depth<0) exit 1
    }
}
END {
    if (depth) exit 1
    # Callback arguments follow the staged cfg80211 header, not the SoC kernel.
    for (i=1; i<=NR; i++) {
        if (lines[i] ~ /^static int rwnx_cfg80211_set_tx_power\(/) {
            signature=lines[i] lines[i+1] lines[i+2] lines[i+3]
            add_tx_radio=tx_radio && signature !~ /radio_idx/
        }
        if (lines[i] ~ /^static int rwnx_cfg80211_set_monitor_channel\(/) {
            signature=lines[i] lines[i+1] lines[i+2] lines[i+3]
            add_monitor_dev=monitor_dev && signature !~ /struct net_device/
        }
    }
    if (lines[1] != "/* OpenWrt supplies cfg80211 independently of the target kernel. */") {
        print "/* OpenWrt supplies cfg80211 independently of the target kernel. */"
        print "#include <linux/version.h>"
        print "#ifndef CFG80211_VERSION"
        print "#define CFG80211_VERSION LINUX_VERSION_CODE"
        print "#endif"
    }
    for (i=1; i<=NR; i++) {
        line=lines[i]
        if (timer_api) {
            gsub(/del_timer_sync[[:space:]]*\(/, "timer_delete_sync(", line)
            gsub(/del_timer[[:space:]]*\(/, "timer_delete(", line)
        }
        if (namespace_strings && line ~ /MODULE_IMPORT_NS\([a-zA-Z_][a-zA-Z0-9_]*\)/) {
            sub(/MODULE_IMPORT_NS\(/, "MODULE_IMPORT_NS(\"", line)
            sub(/\);/, "\");", line)
        }
        if (wiphy_radio && line ~ /^static int rwnx_cfg80211_set_wiphy_params\(/ && line !~ /radio_idx/)
            sub(/u32 changed/, "int radio_idx, u32 changed", line)
        if (add_monitor_dev && line !~ /^static int /)
            gsub(/rwnx_cfg80211_set_monitor_channel\(wiphy,/, "rwnx_cfg80211_set_monitor_channel(wiphy, NULL,", line)
        print line
        if (add_tx_radio && line ~ /^static int rwnx_cfg80211_set_tx_power\(/)
            print "\tint radio_idx,"
        if (add_monitor_dev && line ~ /^static int rwnx_cfg80211_set_monitor_channel\(/)
            print "\tstruct net_device *dev,"
    }
}
