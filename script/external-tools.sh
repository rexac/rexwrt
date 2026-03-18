#!/bin/bash
#=================================================
# File name: external-tools.sh
# System Required: Linux
# Version: 1.0
# Lisence: GPL-3.0
# Author: Rex
# Blog: https://rexe.cc
#=================================================

set -e

get_container_tag() {
  local branch="$1"
  if [[ "$branch" == "main" ]]; then
    echo "latest"
  elif [[ "$branch" =~ ^openwrt-[0-9]{2}\.[0-9]{2}$ ]]; then
    echo "$branch"
  elif [[ "$branch" =~ ^v([0-9]{2}\.[0-9]{2})\. ]]; then
    echo "openwrt-${BASH_REMATCH[1]}"
  else
    local ver
    ver=$(echo "$branch" | grep -oE '[0-9]{2}\.[0-9]{2}' | head -1)
    [[ -n "$ver" ]] && echo "openwrt-$ver" || echo "latest"
  fi
}

CONTAINER_TAG=$(get_container_tag "${BRANCH}")
CONTAINER_IMAGE="ghcr.io/openwrt/tools:${CONTAINER_TAG}"

echo "Checking prebuilt tools container: ${CONTAINER_IMAGE}"

if ! docker manifest inspect "${CONTAINER_IMAGE}" > /dev/null 2>&1; then
  echo "Warning: ${CONTAINER_IMAGE} not found, falling back to ghcr.io/openwrt/tools:latest"
  CONTAINER_IMAGE="ghcr.io/openwrt/tools:latest"
  if ! docker manifest inspect "${CONTAINER_IMAGE}" > /dev/null 2>&1; then
    echo "Error: Prebuilt tools container unavailable. Skipping ext-tools setup."
    exit 0
  fi
fi

echo "Installing prebuilt host tools from ${CONTAINER_IMAGE} ..."

CONTAINER_ID=$(docker create "${CONTAINER_IMAGE}")

mkdir -p "${OPENWRTROOT}/staging_dir" "${OPENWRTROOT}/build_dir"
docker cp "${CONTAINER_ID}:/prebuilt_tools/staging_dir/host" - | tar -xf - -C "${OPENWRTROOT}/staging_dir"
docker cp "${CONTAINER_ID}:/prebuilt_tools/build_dir/host" - | tar -xf - -C "${OPENWRTROOT}/build_dir"

docker rm "${CONTAINER_ID}"

cd "${OPENWRTROOT}"
./scripts/ext-tools.sh --refresh

echo "Prebuilt host tools ready. 'make tools/compile' will be skipped."
