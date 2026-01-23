# Function to clone a repository and extract a specific directory
clone_and_extract() {
  repo_url=$1
  target_path=$2
  target_dir=../$(basename $target_path)
  branch=$3
  git clone --depth 1 --filter=blob:none --sparse ${branch:+--branch=$branch} $repo_url temp
  pushd temp
  git sparse-checkout init --cone
  git sparse-checkout set $target_path
  mkdir -p $target_dir && mv -v $target_path/* $target_dir
  popd
  rm -rf temp
}

# Remove duplicate packages
pushd $OPENWRTROOT/feeds/luci/applications
rm -rf luci-app-argon-config luci-app-cpufreq luci-app-diskman luci-app-mosdns luci-app-openclash luci-app-tailscale || true
popd

pushd $OPENWRTROOT/feeds/luci/themes
rm -rf luci-theme-argon || true
popd

pushd $OPENWRTROOT/feeds/packages/utils
rm -rf coremark || true
popd

# Enter the "package" directory.
cd $OPENWRTROOT/package


# Add custom setup script
cp $GITHUB_WORKSPACE/script/init-settings.sh base-files/files/etc/uci-defaults/99-init-settings
chmod 755 base-files/files/etc/uci-defaults/99-init-settings

# Add autocore-arm
git clone https://github.com/sbwml/autocore-arm

# Add coremark
clone_and_extract https://github.com/coolsnowwolf/packages utils/coremark

# Add luci-app-cpufreq
clone_and_extract https://github.com/immortalwrt/luci applications/luci-app-cpufreq
clone_and_extract https://github.com/immortalwrt/immortalwrt package/emortal/cpufreq

# Add luci-app-diskman
mkdir parted
wget https://raw.githubusercontent.com/lisaac/luci-app-diskman/master/Parted.Makefile -O parted/Makefile
clone_and_extract https://github.com/lisaac/luci-app-diskman applications/luci-app-diskman

# Add luci-app-easytier
if [ ! -d "$OPENWRTROOT/feeds/luci/applications/luci-app-easytier" ]; then
  git clone https://github.com/EasyTier/luci-app-easytier
fi

# Add luci-app-irqbalance
if [ ! -d "$OPENWRTROOT/feeds/luci/applications/luci-app-irqbalance" ]; then
  clone_and_extract https://github.com/openwrt/luci applications/luci-app-irqbalance
fi

# Add luci-app-mosdns
# drop mosdns and v2ray-geodata packages that come with the source
find ../ | grep Makefile | grep v2ray-geodata | xargs rm -f
find ../ | grep Makefile | grep mosdns | xargs rm -f
git clone https://github.com/sbwml/luci-app-mosdns -b v5 mosdns
git clone https://github.com/sbwml/v2ray-geodata

# Add luci-app-openlist
if [ ! -d "$OPENWRTROOT/feeds/luci/applications/luci-app-openlist" ]; then
  clone_and_extract https://github.com/openwrt/packages net/openlist
  clone_and_extract https://github.com/openwrt/luci applications/luci-app-openlist
fi

# Add luci-app-tailscale
git clone https://github.com/asvow/luci-app-tailscale

# Add luci-app-zerotier
if [ ! -d "$OPENWRTROOT/feeds/luci/applications/luci-app-zerotier" ]; then
  rm -rf $OPENWRTROOT/feeds/packages/net/zerotier
  clone_and_extract https://github.com/immortalwrt/packages net/zerotier
  clone_and_extract https://github.com/immortalwrt/luci applications/luci-app-zerotier
fi

# Add luci-theme-argon
clone_and_extract https://github.com/immortalwrt/luci themes/luci-theme-argon
clone_and_extract https://github.com/immortalwrt/luci applications/luci-app-argon-config

# Add Nikki
if [ ! -d "$OPENWRTROOT/feeds/luci/applications/luci-app-nikki" ]; then
  clone_and_extract https://github.com/nikkinikki-org/OpenWrt-nikki nikki
  clone_and_extract https://github.com/nikkinikki-org/OpenWrt-nikki luci-app-nikki
fi

# Add NanoHatOLED
if [ "$DEVICE" == "nanopi-neo2-black" ]; then
  mkdir NanoHatOLED
  wget -O NanoHatOLED/Makefile https://github.com/rexac/NanoHatOLED/raw/main/Makefile
fi

# Return to "openwrt" directory.
cd $OPENWRTROOT

# Execute all patch & preset shell files in the script directory.
find $GITHUB_WORKSPACE/script/ -maxdepth 1 \( -name "patch-*.sh" -o -name "preset-*.sh" \) -exec {} \;
