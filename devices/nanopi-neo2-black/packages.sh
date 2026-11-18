#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$OPENWRTROOT/package/NanoHatOLED"
curl -fLSs --retry 3 https://github.com/rexac/NanoHatOLED/raw/main/Makefile \
  -o "$OPENWRTROOT/package/NanoHatOLED/Makefile"
