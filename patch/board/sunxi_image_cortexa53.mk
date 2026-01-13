define Device/friendlyarm_nanopi-neo2-black
  DEVICE_VENDOR := FriendlyARM
  DEVICE_MODEL := NanoPi NEO2 Black
  SUPPORTED_DEVICES += nanopi-neo2-black
  $(Device/sun50i-h5)
endef
TARGET_DEVICES += friendlyarm_nanopi-neo2-black
