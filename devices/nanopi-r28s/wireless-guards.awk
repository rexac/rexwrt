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
    print "/* OpenWrt supplies cfg80211 independently of the target kernel. */"
    print "#include <linux/version.h>"
    print "#ifndef CFG80211_VERSION"
    print "#define CFG80211_VERSION LINUX_VERSION_CODE"
    print "#endif"
    for (i=1; i<=NR; i++) print lines[i]
}
