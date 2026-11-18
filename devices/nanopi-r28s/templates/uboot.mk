include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=uboot-rexwrt-r28s
PKG_VERSION:=@BOOT@
PKG_RELEASE:=1
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/u-boot/u-boot.git
PKG_SOURCE_VERSION:=@BOOT@
PKG_MIRROR_HASH:=skip
UBOOT_USE_BINMAN:=1
UBOOT_USE_INTREE_DTC:=1

include $(INCLUDE_DIR)/u-boot.mk
include $(INCLUDE_DIR)/package.mk

define U-Boot/Default
  BUILD_TARGET:=rockchip
  BUILD_SUBTARGET:=armv8
  HIDDEN:=1
endef

define U-Boot/rexwrt-r28s
  NAME:=NanoPi R28S (official upstream)
  UBOOT_CONFIG:=@BOOTCONFIG@
  BUILD_DEVICES:=friendlyarm_nanopi-r28s
endef

UBOOT_TARGETS:=rexwrt-r28s
UBOOT_CONFIGURE_VARS+=USE_PRIVATE_LIBGCC=yes
UBOOT_CUSTOMIZE_CONFIG:= \
	--disable TOOLS_MKEFICAPSULE \
	--enable USE_BOOTCOMMAND \
	--set-str BOOTCOMMAND 'setenv soc rk3528; setenv devtype mmc; setenv devnum 1; if load mmc 1:1 0x00c00000 boot.scr; then source 0x00c00000; fi; setenv devnum 0; if load mmc 0:1 0x00c00000 boot.scr; then source 0x00c00000; fi' \
	--enable HUSH_PARSER --enable CMD_SOURCE --enable CMD_EXT4 --enable CMD_FS_GENERIC \
	--enable CMD_PART --enable CMD_BOOTM --enable LZMA \
	--set-str MKIMAGE_DTC_PATH $(PKG_BUILD_DIR)/scripts/dtc/dtc
UBOOT_MAKE_FLAGS+= \
	BL31=$(PKG_BUILD_DIR)/@BL31@ \
	ROCKCHIP_TPL=$(PKG_BUILD_DIR)/@DDR@

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./files/*.bin ./files/*.elf $(PKG_BUILD_DIR)/
endef

define Build/InstallDev
	$(INSTALL_DIR) $(STAGING_DIR_IMAGE)
	$(CP) $(PKG_BUILD_DIR)/u-boot-rockchip.bin $(STAGING_DIR_IMAGE)/rexwrt-r28s-u-boot-rockchip.bin
endef

define Package/u-boot/install/default
endef

$(eval $(call BuildPackage/U-Boot))
