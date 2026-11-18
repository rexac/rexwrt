include $(TOPDIR)/rules.mk

PKG_NAME:=aic8800-sdio
PKG_VERSION:=@AIC@
PKG_RELEASE:=1
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/radxa-pkg/aic8800.git
PKG_SOURCE_VERSION:=@AIC@
PKG_MIRROR_HASH:=skip
PKG_LICENSE:=GPL-2.0
PKG_BUILD_PARALLEL:=1
PKG_BUILD_DEPENDS:=mac80211
STAMP_CONFIGURED_DEPENDS:=$(STAGING_DIR)/usr/include/mac80211-backport/backport/autoconf.h

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

AIC_DIR=$(PKG_BUILD_DIR)/src/SDIO/driver_fw/driver/aic8800
CFG80211_VERSION:=$(shell sed -n 's/^PKG_VERSION:=//p' $(TOPDIR)/package/kernel/mac80211/Makefile | \
	awk -F. 'NF >= 2 && $$1 ~ /^[0-9]+$$/ && $$2 ~ /^[0-9]+$$/ {print $$1*65536+$$2*256+(($$3+0)>255?255:$$3+0)}')
ifeq ($(CFG80211_VERSION),)
  $(error Cannot detect OpenWrt cfg80211 backport version)
endif

define KernelPackage/aic8800-sdio
  SUBMENU:=Wireless Drivers
  TITLE:=Radxa AIC8800 SDIO Wi-Fi
  DEPENDS:=@TARGET_rockchip_armv8 +kmod-cfg80211 +kmod-mmc +aic8800-sdio-firmware
  FILES:= \
	$(AIC_DIR)/aic8800_bsp/aic8800_bsp.ko \
	$(AIC_DIR)/aic8800_fdrv/aic8800_fdrv.ko
  AUTOLOAD:=$(call AutoProbe,aic8800_bsp aic8800_fdrv)
endef

define Package/aic8800-sdio-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=Radxa AIC8800 SDIO Wi-Fi and Bluetooth firmware
  PKGARCH:=all
  LICENSE:=Proprietary
endef

define KernelPackage/r28s-bluetooth
  SUBMENU:=Bluetooth Support
  TITLE:=NanoPi R28S AIC8800 UART Bluetooth
  DEPENDS:=@TARGET_rockchip_armv8 +kmod-hci-uart +kmod-aic8800-sdio
  KCONFIG:= \
	CONFIG_SERIAL_DEV_BUS=y \
	CONFIG_SERIAL_DEV_CTRL_TTYPORT=y \
	CONFIG_BT_HCIUART_SERDEV=y \
	CONFIG_BT_HCIUART_H4=y \
	CONFIG_BT_HCIUART_AIC=y
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	bash ./prepare.sh $(PKG_BUILD_DIR)
endef

NOSTDINC_FLAGS:= \
	$(KERNEL_NOSTDINC_FLAGS) \
	-DCFG80211_VERSION=$(CFG80211_VERSION) \
	-I$(STAGING_DIR)/usr/include/mac80211-backport \
	-I$(STAGING_DIR)/usr/include/mac80211-backport/uapi \
	-I$(STAGING_DIR)/usr/include/mac80211 \
	-I$(STAGING_DIR)/usr/include/mac80211/uapi \
	-include backport/backport.h

define Build/Compile
	+$(KERNEL_MAKE) $(PKG_JOBS) M=$(AIC_DIR) \
		CONFIG_AIC8800_BTLPM_SUPPORT= CONFIG_AIC8800_WLAN_SUPPORT=m CONFIG_AIC_WLAN_SUPPORT=m \
		CONFIG_PLATFORM_UBUNTU=y NOSTDINC_FLAGS="$(NOSTDINC_FLAGS)" modules
endef

define Package/aic8800-sdio-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/aic8800_fw/SDIO
	$(CP) $(PKG_BUILD_DIR)/src/SDIO/driver_fw/fw/. $(1)/lib/firmware/aic8800_fw/SDIO/
endef

$(eval $(call KernelPackage,aic8800-sdio))
$(eval $(call KernelPackage,r28s-bluetooth))
$(eval $(call BuildPackage,aic8800-sdio-firmware))
