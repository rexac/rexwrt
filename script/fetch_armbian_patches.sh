#!/usr/bin/env bash
#=================================================
# File name: fetch_armbian_patches.sh
# Description: Fetch kernel and U-Boot patches for nanopi-neo-core2 from Armbian,
#              convert them for nanopi-neo2-black and inject additional hardware nodes
#              (e.g., cpu-opp, ehci1, ohci1, i2c0) into the corresponding DTS.
# Usage: ./fetch_armbian_patches.sh [--dry-run] [--force] [--kernel-only] [--uboot-only] [--openwrt-root=<path>]
# System Required: Linux
# Version: 1.0
# Lisence: GPL-3.0
# Author: Rex
# Blog: https://rexe.cc
#=================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# === Parameter Parsing ===
DRY_RUN=0
FORCE=0
KERNEL_ONLY=0
UBOOT_ONLY=0
OPENWRT_ROOT=""

for arg in "$@"; do
    case $arg in
        --dry-run)     DRY_RUN=1 ;;
        --force)       FORCE=1 ;;
        --kernel-only) KERNEL_ONLY=1 ;;
        --uboot-only)  UBOOT_ONLY=1 ;;
        --openwrt-root=*) OPENWRT_ROOT="${arg#*=}" ;;
        *) echo "Unknown parameter: $arg"; exit 1 ;;
    esac
done

if [ "$KERNEL_ONLY" -eq 1 ] && [ "$UBOOT_ONLY" -eq 1 ]; then
    echo "Cannot specify both --kernel-only and --uboot-only."
    exit 1
fi
if [ "$KERNEL_ONLY" -eq 0 ] && [ "$UBOOT_ONLY" -eq 0 ]; then
    DO_KERNEL=1; DO_UBOOT=1
elif [ "$KERNEL_ONLY" -eq 1 ]; then
    DO_KERNEL=1; DO_UBOOT=0
else
    DO_KERNEL=0; DO_UBOOT=1
fi
UBOOT_FAILED=0

if [ -z "$OPENWRT_ROOT" ]; then
    # Attempt to detect the openwrt folder in the current directory by default, or provide via environment variables
    if [ -n "$OPENWRTROOT" ] && [ -d "$OPENWRTROOT" ]; then
        OPENWRT_ROOT="$OPENWRTROOT"
    elif [ -d "$PWD/openwrt" ]; then
        OPENWRT_ROOT="$PWD/openwrt"
    else
        echo "[✗] Error: Please specify the OpenWrt source directory via --openwrt-root=/path/to/openwrt, or set the OPENWRTROOT environment variable."
        exit 1
    fi
fi

[ "$DRY_RUN" -eq 1 ] && echo "[⚠] === Dry-run mode (no files will be written) ==="

# === Dynamic Version Detection ===
echo "=== Detecting OpenWrt Environment ==="
if [ ! -f "$OPENWRT_ROOT/target/linux/sunxi/Makefile" ]; then
    echo "[✗] Error: Cannot find target/linux/sunxi/Makefile in $OPENWRT_ROOT"
    exit 1
fi
KERNEL_VER_DETECT=$(grep -E '^KERNEL_PATCHVER:=' "$OPENWRT_ROOT/target/linux/sunxi/Makefile" | cut -d'=' -f2)
UBOOT_VER_DETECT=$(grep -E '^PKG_VERSION:=' "$OPENWRT_ROOT/package/boot/uboot-sunxi/Makefile" | cut -d'=' -f2)

if [ -z "$KERNEL_VER_DETECT" ]; then
    echo "[✗] Error: Failed to extract KERNEL_PATCHVER from the source tree"
    exit 1
fi
if [ -z "$UBOOT_VER_DETECT" ]; then
    echo "[✗] Error: Failed to extract PKG_VERSION (U-Boot) from the source tree"
    exit 1
fi

echo "[✓] Detected current OpenWrt (sunxi) target kernel version: ${KERNEL_VER_DETECT}"
echo "[✓] Detected current OpenWrt (sunxi) target U-Boot version: ${UBOOT_VER_DETECT}"

# Map to names defined by Armbian
SUNXI_VERSIONS=("sunxi-${KERNEL_VER_DETECT}")

BASE_URL="https://raw.githubusercontent.com/armbian/build/main"
KNOWN_CORE2_PATCH="arm64-dts-Add-sun50i-h5-nanopi-neo-core2-device.patch"
TARGET_NAME="001-arm64-dts-Add-sun50i-h5-nanopi-neo2-black-device.patch"

# === Conversion Logic (AWK Script) ===
cat << 'EOF' > /tmp/transform_patch.awk
BEGIN {
    # Dynamically inject the CPU_OPP environment variable during shell processing
}
{
    # Ignore double-dash footer lines typical in armbian patches
    if ($0 ~ /^-- $/ || $0 == "Armbian" || $0 ~ /^[0-9]\.[0-9]+\.[0-9]+$/) {
        next
    }

    # Clean up dummy index hashes from Armbian but keep line for git am compatibility
    if ($0 ~ /^index (111111111111\.\.222222222222|000000000000\.\.111111111111)/) {
        sub(/111111111111\.\.222222222222/, "000000000000..111111111111", $0)
        print $0
        next
    }

    # Name replacements
    gsub(/sun50i-h5-nanopi-neo-core2/, "sun50i-h5-nanopi-neo2-black")
    gsub(/nanopi-neo-core2/, "nanopi-neo2-black")
    gsub(/nanopi_neo_core2/, "nanopi_neo2_black")
    gsub(/friendlyarm,nanopi-neo-core2/, "friendlyarm,nanopi-neo2-black")
    gsub(/FriendlyARM NanoPi NEO Core 2/, "FriendlyARM NanoPi NEO2 Black")
    gsub(/FriendlyARM NanoPi NEO Core2/, "FriendlyARM NanoPi NEO2 Black")

    # Fix Makefile hunk line order
    if ($0 ~ /sun50i-h5-nanopi-neo2\.dtb/ && pending_makefile_black) {
        print "+dtb-$(CONFIG_ARCH_SUNXI) += sun50i-h5-nanopi-neo2-black.dtb"
        print $0
        pending_makefile_black = 0
        next
    }

    # Inject dynamic OPP patch block before the main dts diff
    if ($0 ~ /^diff --git a\/arch\/arm64\/boot\/dts\/allwinner\/sun50i-h5-nanopi-neo2-black.dts/) {
        if (!opp_injected && "OPP_HUNK_FILE" in ENVIRON && ENVIRON["OPP_HUNK_FILE"] != "") {
            while ((getline hunk_line < ENVIRON["OPP_HUNK_FILE"]) > 0) print hunk_line
            opp_injected = 1
        }
    }

    # Inject include cpu-opp.dtsi
    if ($0 == "+#include \"sun50i-h5.dtsi\"") {
        print $0
        if (ENVIRON["INJECT_OPP_INCLUDE"] != "0") {
            print "+#include \"sun50i-h5-cpu-opp.dtsi\""
        }
        next
    }

    print $0

    # Inject device nodes
    line[3] = line[2]; line[2] = line[1]; line[1] = $0;
    
    if (line[3] == "+&ehci0 {" && line[2] == "+\tstatus = \"okay\";" && line[1] == "+};" && !ehci1_inj) {
        print "+\n+&ehci1 {\n+\tstatus = \"okay\";\n+};"
        ehci1_inj = 1
    }
    if (line[3] == "+\tcap-mmc-hw-reset;" && line[2] == "+\tstatus = \"okay\";" && line[1] == "+};" && !i2c_inj) {
        print "+\n+&i2c0 {\n+\tpinctrl-names = \"default\";\n+\tpinctrl-0 = <&i2c0_pins>;\n+\tstatus = \"okay\";\n+\tclock-frequency = <400000>;\n+};"
        i2c_inj = 1
    }
    if (line[3] == "+&ohci0 {" && line[2] == "+\tstatus = \"okay\";" && line[1] == "+};" && !ohci1_inj) {
        print "+\n+&ohci1 {\n+\tstatus = \"okay\";\n+};"
        ohci1_inj = 1
    }
}
EOF

# === Kernel Processing =======================================================
if [ "$DO_KERNEL" -eq 1 ]; then
    echo "=== Fetching Kernel Patches ==="
    for ver_dir in "${SUNXI_VERSIONS[@]}"; do
        # Get actual minor kernel version (e.g. 6.6, 6.12)
        base_ver="${ver_dir#sunxi-}"
        base_ver="${base_ver#dev-}"
        export KERN_VER_TAG="v${base_ver}"
        
        target_dir="$REPO_ROOT/patch/kernel/sunxi/patches-${base_ver}"
        target_file="$target_dir/$TARGET_NAME"
        
        if [ -f "$target_file" ] && [ "$FORCE" -eq 0 ]; then
            echo "[·] Skipping existing: patch/kernel/sunxi/patches-${base_ver}/${TARGET_NAME}"
            continue
        fi
        
        patch_url="${BASE_URL}/patch/kernel/archive/${ver_dir}/patches.armbian/${KNOWN_CORE2_PATCH}"
        
        echo "[I] Downloading and converting ${ver_dir} ..."
        
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [DRY] curl $patch_url -> $target_file"
            continue
        fi
        
        # Attempt to download patch or fallback to DTS
        patch_ready=0
        if curl -f -s -S "$patch_url" -o /tmp/raw.patch; then
            patch_ready=1
        else
            echo "  [I] Patch not found, attempting to construct it from DTS ..."
            dts_url="${BASE_URL}/patch/kernel/archive/${ver_dir}/dt_64/sun50i-h5-nanopi-neo-core2.dts"
            if curl -f -s -S "$dts_url" -o /tmp/raw_core2.dts; then
                kern_makefile_url="https://raw.githubusercontent.com/torvalds/linux/${KERN_VER_TAG}/arch/arm64/boot/dts/allwinner/Makefile"
                if curl -f -s -S "$kern_makefile_url" -o /tmp/kernel_makefile_base; then
                    rm -rf /tmp/gen_raw_patch
                    mkdir -p /tmp/gen_raw_patch/arch/arm64/boot/dts/allwinner
                    cp /tmp/kernel_makefile_base /tmp/gen_raw_patch/arch/arm64/boot/dts/allwinner/Makefile
                    
                    (
                        cd /tmp/gen_raw_patch
                        git init -q
                        git config user.email "github-actions@users.noreply.github.com"
                        git config user.name "github-actions"
                        git add arch
                        git commit -m "base" -q
                        
                        awk '{ 
                            print $0
                            if ($0 ~ /^dtb-\$\(CONFIG_ARCH_SUNXI\) \+= sun50i-h5-nanopi-neo2\.dtb[[:space:]]*$/) {
                                print "dtb-$(CONFIG_ARCH_SUNXI) += sun50i-h5-nanopi-neo-core2.dtb"
                            }
                        }' arch/arm64/boot/dts/allwinner/Makefile > arch/arm64/boot/dts/allwinner/Makefile.new
                        mv arch/arm64/boot/dts/allwinner/Makefile.new arch/arm64/boot/dts/allwinner/Makefile
                        
                        cp /tmp/raw_core2.dts arch/arm64/boot/dts/allwinner/sun50i-h5-nanopi-neo-core2.dts
                        git add arch
                        git diff --cached > /tmp/raw.patch || true
                    )
                    
                    if [ -s "/tmp/raw.patch" ]; then
                        echo "  [✓] Successfully generated /tmp/raw.patch from DTS"
                        patch_ready=1
                    else
                        echo "  [✗] Failed to generate raw patch, skipping."
                    fi
                else
                    echo "  [✗] Failed to fetch base Makefile, cannot generate patch."
                fi
            else
                echo "  [⚠] Patch and DTS not found for version ( ${ver_dir} ), skipping."
            fi
        fi

        if [ "$patch_ready" -eq 1 ]; then
            mkdir -p "$target_dir"
            
            # KERN_VER_TAG is already exported
            export KERN_HUNK_FILE="/tmp/kernel_makefile_hunk"
            export OPP_HUNK_FILE="/tmp/kernel_opp.patch"
            rm -f "$OPP_HUNK_FILE" "$KERN_HUNK_FILE"
            
            if grep -q '+#include "sun50i-h5-cpu-opp.dtsi"' /tmp/raw.patch; then
                export INJECT_OPP_INCLUDE=0
            else
                export INJECT_OPP_INCLUDE=1
            fi
            
            # --- [Dynamically fetch CPU_OPP to generate accurate context] ---
            kern_opp_url="https://raw.githubusercontent.com/torvalds/linux/${KERN_VER_TAG}/arch/arm64/boot/dts/allwinner/sun50i-h5-cpu-opp.dtsi"
            echo "  [I] Fetching Kernel ${KERN_VER_TAG} CPU_OPP to generate real diff ..."
            if curl -f -s -S "$kern_opp_url" -o /tmp/kernel_opp; then
                awk '{
                    print $0
                    if ($0 ~ /opp-1152000000 \{/) { in_opp=1 }
                    if (in_opp && $0 ~ /^[[:space:]]*};/) {
                        in_opp=0
                        print ""
                        print "\t\topp-1200000000 {"
                        print "\t\t\topp-hz = /bits/ 64 <1200000000>;"
                        print "\t\t\topp-microvolt = <1300000 1300000 1300000>;"
                        print "\t\t\tclock-latency-ns = <244144>; /* 8 32k periods */"
                        print "\t\t};"
                        print ""
                        print "\t\topp-1224000000 {"
                        print "\t\t\topp-hz = /bits/ 64 <1224000000>;"
                        print "\t\t\topp-microvolt = <1300000 1300000 1300000>;"
                        print "\t\t\tclock-latency-ns = <244144>; /* 8 32k periods */"
                        print "\t\t};"
                        print ""
                        print "\t\topp-1248000000 {"
                        print "\t\t\topp-hz = /bits/ 64 <1248000000>;"
                        print "\t\t\topp-microvolt = <1300000 1300000 1300000>;"
                        print "\t\t\tclock-latency-ns = <244144>; /* 8 32k periods */"
                        print "\t\t};"
                        print ""
                        print "\t\topp-1296000000 {"
                        print "\t\t\topp-hz = /bits/ 64 <1296000000>;"
                        print "\t\t\topp-microvolt = <1300000 1300000 1300000>;"
                        print "\t\t\tclock-latency-ns = <244144>; /* 8 32k periods */"
                        print "\t\t};"
                    }
                }' /tmp/kernel_opp > /tmp/kernel_opp.new
                
                if grep -q "opp-1200000000" /tmp/kernel_opp.new; then
                    rm -rf /tmp/gen_patch_opp
                    mkdir -p /tmp/gen_patch_opp/a/arch/arm64/boot/dts/allwinner
                    mkdir -p /tmp/gen_patch_opp/b/arch/arm64/boot/dts/allwinner
                    cp /tmp/kernel_opp /tmp/gen_patch_opp/a/arch/arm64/boot/dts/allwinner/sun50i-h5-cpu-opp.dtsi
                    cp /tmp/kernel_opp.new /tmp/gen_patch_opp/b/arch/arm64/boot/dts/allwinner/sun50i-h5-cpu-opp.dtsi
                    (cd /tmp/gen_patch_opp && git diff --no-index --no-prefix a/arch/arm64/boot/dts/allwinner/sun50i-h5-cpu-opp.dtsi b/arch/arm64/boot/dts/allwinner/sun50i-h5-cpu-opp.dtsi > "$OPP_HUNK_FILE" || true)
                else
                    echo "  [⚠] Cannot find insertion point in OPP file, skipping OPP node injection."
                    rm -f "$OPP_HUNK_FILE"
                fi
            else
                echo "  [⚠] Failed to fetch OPP file for Kernel ${KERN_VER_TAG}, skipping OPP node injection."
            fi
            
            awk -f /tmp/transform_patch.awk /tmp/raw.patch > "$target_file.tmp"
            
            # Srictly recalculate the hunk size for the new DTS file
            awk '
            { lines[NR] = $0 }
            /^diff --git a\/arch\/arm64\/boot\/dts\/allwinner\/sun50i-h5-nanopi-neo2-black\.dts/ { in_target = 1 }
            /^@@ -0,0 \+1,[0-9]+ @@/ {
                if (in_target) {
                    hunk_header_line = NR
                    plus_count = 0
                    in_hunk = 1
                }
            }
            {
                if (in_hunk && NR > hunk_header_line) {
                    if (/^diff --git/ || /^-- $/) {
                        in_hunk = 0
                        in_target = 0
                        lines[hunk_header_line] = "@@ -0,0 +1," plus_count " @@"
                    } else if (/^\+/ || /^ / || /^-/) {
                        plus_count++
                    }
                }
            }
            END {
                if (in_hunk) {
                    lines[hunk_header_line] = "@@ -0,0 +1," plus_count " @@"
                }
                for (i=1; i<=NR; i++) print lines[i]
            }
            ' "$target_file.tmp" > "$target_file"
            rm -f "$target_file.tmp"
            
            # --- [Dynamically fetch kernel corresponding version Makefile to generate accurate context] ---
            kern_makefile_url="https://raw.githubusercontent.com/torvalds/linux/${KERN_VER_TAG}/arch/arm64/boot/dts/allwinner/Makefile"
            echo "  [I] Fetching Kernel ${KERN_VER_TAG} Makefile to generate real diff ..."
            
            if [ -f /tmp/kernel_makefile_base ] && cp /tmp/kernel_makefile_base /tmp/kernel_makefile || curl -f -s -S "$kern_makefile_url" -o /tmp/kernel_makefile; then
                awk '{ 
                    print $0
                    # Match neo2.dtb and insert neo2-black.dtb after it
                    if ($0 ~ /^dtb-\$\(CONFIG_ARCH_SUNXI\) \+= sun50i-h5-nanopi-neo2\.dtb[[:space:]]*$/) {
                        print "dtb-$(CONFIG_ARCH_SUNXI) += sun50i-h5-nanopi-neo2-black.dtb"
                    }
                }' /tmp/kernel_makefile > /tmp/kernel_makefile.new
                
                if grep -q "sun50i-h5-nanopi-neo2-black.dtb" /tmp/kernel_makefile.new; then
                    rm -rf /tmp/gen_patch_mk
                    mkdir -p /tmp/gen_patch_mk/a/arch/arm64/boot/dts/allwinner
                    mkdir -p /tmp/gen_patch_mk/b/arch/arm64/boot/dts/allwinner
                    cp /tmp/kernel_makefile /tmp/gen_patch_mk/a/arch/arm64/boot/dts/allwinner/Makefile
                    cp /tmp/kernel_makefile.new /tmp/gen_patch_mk/b/arch/arm64/boot/dts/allwinner/Makefile
                    (cd /tmp/gen_patch_mk && git diff --no-index --no-prefix a/arch/arm64/boot/dts/allwinner/Makefile b/arch/arm64/boot/dts/allwinner/Makefile > "$KERN_HUNK_FILE" || true)
                    awk '
                    BEGIN { in_mk=0 }
                    /^diff --git a\/arch\/arm64\/boot\/dts\/allwinner\/Makefile/ {
                        while ((getline line < ENVIRON["KERN_HUNK_FILE"]) > 0) print line
                        in_mk=1
                        next
                    }
                    /^diff --git / && in_mk { in_mk=0; print $0; next }
                    in_mk { next }
                    { print $0 }
                    ' "$target_file" > /tmp/kernel_target.tmp
                    mv /tmp/kernel_target.tmp "$target_file"
                else
                    echo "  [⚠] Abnormal Kernel Makefile structure, failed to insert config, skipping dynamic context."
                fi
            else
                echo "  [⚠] Failed to fetch Makefile for Kernel ${KERN_VER_TAG}, using default context."
            fi
            # -------------------------------------------------------------
            
            # --- [Dynamically update real diffstat] ---
            echo "  [I] Dynamically recalculating real diffstat ..."
            if git apply --stat --summary "$target_file" > /tmp/patch_stat.tmp; then
                awk '
                BEGIN { in_header=0; stat_injected=0 }
                /^---$/ { print $0; in_header=1; next }
                /^diff --git / {
                    if (!stat_injected && in_header) {
                        while ((getline stat_line < "/tmp/patch_stat.tmp") > 0) print stat_line
                        print ""
                        stat_injected = 1
                    }
                    in_header=0
                    print $0
                    next
                }
                in_header {
                    # Discard native original diffstat
                    next
                }
                { print $0 }
                ' "$target_file" > /tmp/target_stat.tmp
                mv /tmp/target_stat.tmp "$target_file"
            else
                echo "  [⚠] git apply --stat failed, attempting to keep original diffstat"
            fi
            
            echo "[✓] Written: patch/kernel/sunxi/patches-${base_ver}/${TARGET_NAME}"
        fi
    done
fi
echo ""

# === U-Boot Processing =======================================================
if [ "$DO_UBOOT" -eq 1 ]; then
    echo "=== Fetching U-Boot Patches ==="
    UB_PATCH_URL="${BASE_URL}/patch/u-boot/u-boot-sunxi/board_nanopineocore2/add-xx-nanopineocore2.patch"
    TARGET_UB_NAME="001-add-sun50i-h5-nanopi-neo2-black-device.patch"
    
    echo "[I] Downloading U-Boot patch ..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [DRY] curl $UB_PATCH_URL"
    else
        if curl -f -s -S "$UB_PATCH_URL" -o /tmp/raw_uboot.patch; then
            # Simple name replacements
            sed -e 's/sun50i-h5-nanopi-neo-core2/sun50i-h5-nanopi-neo2-black/g' \
                -e 's/nanopi-neo-core2/nanopi-neo2-black/g' \
                -e 's/nanopi_neo_core2/nanopi_neo2_black/g' \
                -e 's/NANOPI_NEO_CORE2/NANOPI_NEO2_BLACK/g' \
                -e 's/nanopi neo core2/nanopi neo2 black/g' \
                -e 's/NanoPi NEO Core2/NanoPi NEO2 Black/g' \
                -e 's/NanoPi NEO Core 2/NanoPi NEO2 Black/g' \
                /tmp/raw_uboot.patch > /tmp/transformed_uboot.patch
        else
            echo "[✗] Failed to download U-Boot patch"
            UBOOT_FAILED=1 # Mark as failed
        fi
    fi
    
    if [ "$UBOOT_FAILED" -eq 0 ]; then
        for ub_ver in "$UBOOT_VER_DETECT"; do
            target_dir="$REPO_ROOT/patch/u-boot/uboot-sunxi/patches"
            target_file="$target_dir/$TARGET_UB_NAME"
            
            if [ -f "$target_file" ] && [ "$FORCE" -eq 0 ]; then
                echo "[·] Skipping existing: patch/u-boot/uboot-sunxi/patches/${TARGET_UB_NAME}"
                continue
            fi
            
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "  [DRY] Writing -> $target_file"
            else
                mkdir -p "$target_dir"
                cp /tmp/transformed_uboot.patch "$target_file"
                
                # Dynamically fetch u-boot corresponding version Makefile to generate accurate context
                export UBOOT_VER_TAG="v${ub_ver}"
                export HUNK_FILE="/tmp/uboot_makefile_hunk"
                makefile_url="https://raw.githubusercontent.com/u-boot/u-boot/${UBOOT_VER_TAG}/arch/arm/dts/Makefile"
                echo "  [I] Fetching U-Boot ${UBOOT_VER_TAG} Makefile to generate real diff ..."
                
                if curl -f -s -S "$makefile_url" -o /tmp/uboot_makefile; then
                    awk '{ print $0; if ($0 ~ /sun50i-h5-nanopi-neo2\.dtb *\\/) { print "\tsun50i-h5-nanopi-neo2-black.dtb \\" } }' /tmp/uboot_makefile > /tmp/uboot_makefile.new
                    if grep -q "sun50i-h5-nanopi-neo2-black.dtb" /tmp/uboot_makefile.new; then
                        rm -rf /tmp/gen_patch_uboot
                        mkdir -p /tmp/gen_patch_uboot/a/arch/arm/dts
                        mkdir -p /tmp/gen_patch_uboot/b/arch/arm/dts
                        cp /tmp/uboot_makefile /tmp/gen_patch_uboot/a/arch/arm/dts/Makefile
                        cp /tmp/uboot_makefile.new /tmp/gen_patch_uboot/b/arch/arm/dts/Makefile
                        (cd /tmp/gen_patch_uboot && git diff --no-index --no-prefix a/arch/arm/dts/Makefile b/arch/arm/dts/Makefile > "$HUNK_FILE" || true)
                        awk '
                        BEGIN { in_mk=0 }
                        /^diff --git a\/arch\/arm\/dts\/Makefile/ {
                            while ((getline line < ENVIRON["HUNK_FILE"]) > 0) print line
                            in_mk=1
                            next
                        }
                        /^diff --git / && in_mk { in_mk=0; print $0; next }
                        in_mk { next }
                        { print $0 }
                        ' "$target_file" > /tmp/uboot_target.tmp
                        mv /tmp/uboot_target.tmp "$target_file"
                    else
                        echo "  [⚠] Abnormal Makefile structure, failed to insert config, skipping dynamic context."
                    fi
                else
                    echo "  [⚠] Failed to fetch Makefile for U-Boot ${UBOOT_VER_TAG}, using default context."
                fi
                
                # --- [Dynamically update real diffstat] ---
                echo "  [I] Dynamically recalculating real diffstat ..."
                if git apply --stat --summary "$target_file" > /tmp/patch_stat_uboot.tmp; then
                    awk '
                    BEGIN { in_header=0; stat_injected=0 }
                    /^---$/ { print $0; in_header=1; next }
                    /^diff --git / {
                        if (!stat_injected && in_header) {
                            while ((getline stat_line < "/tmp/patch_stat_uboot.tmp") > 0) print stat_line
                            print ""
                            stat_injected = 1
                        }
                        in_header=0
                        print $0
                        next
                    }
                    in_header {
                        # Discard native original diffstat
                        next
                    }
                    { print $0 }
                    ' "$target_file" > /tmp/uboot_target_stat.tmp
                    mv /tmp/uboot_target_stat.tmp "$target_file"
                else
                    echo "  [⚠] git apply --stat failed, attempting to keep original diffstat"
                fi
                
                echo "[✓] Written: patch/u-boot/uboot-sunxi/patches/${TARGET_UB_NAME}"
            fi
        done
    fi
fi

# Cleanup
rm -rf /tmp/transform_patch.awk /tmp/raw.patch /tmp/raw_uboot.patch /tmp/transformed_uboot.patch \
       /tmp/gen_raw_patch /tmp/gen_patch_opp /tmp/gen_patch_mk /tmp/gen_patch_uboot \
       /tmp/kernel_makefile_base /tmp/raw_core2.dts /tmp/kernel_opp* /tmp/kernel_makefile* \
       /tmp/patch_stat* /tmp/uboot_makefile*
echo "=== Done ==="
