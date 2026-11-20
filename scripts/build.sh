#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./rexwrt COMMAND [OPTIONS]

Commands:
  devices     List supported device names (--json for CI)
  plan        Print resolved configuration and build stages; no changes
  clone       Clone the selected OpenWrt branch/tag
  feeds       Update and install OpenWrt feeds
  adapt       Apply only the selected device's support (--dry-run to preview)
  configure   Load seeds, overlay, device support and common customizations
  download    Download build dependencies
  preflight   Compile kernel and device packages before the full package set
  compile     Compile toolchain, target and packages
  images      Install packages and collect firmware with SHA-256 checksums
  build       Run clone -> feeds -> configure -> download -> compile -> images
  check       Run offline project checks and regression tests

Options:
  --device NAME        Default: nanopi-neo2-black (or DEVICE)
  --branch REF         OpenWrt branch or tag; default: main (or BRANCH)
  --source PATH        OpenWrt checkout; default: work/DEVICE/REF/openwrt
  --jobs NUMBER        Parallel jobs; default: number of host CPUs
  --no-prebuilt        Build host tools and toolchain from source
  --dry-run            Check device adaptation without changing the source
  --json               JSON output for devices

Firmware builds require Linux. devices, plan and check also run on macOS.
EOF
}

command=${1:-help}
if (( $# )); then shift; fi
DEVICE=${DEVICE:-nanopi-neo2-black}
BRANCH=${BRANCH:-main}
OPENWRTROOT=${OPENWRTROOT:-}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}
PREBUILT=${PREBUILT:-1}
dry_run=0
json=0
while (( $# )); do
  case "$1" in
    --device|--branch|--source|--jobs)
      (( $# >= 2 )) || die "Missing value for $1"
      case "$1" in
        --device) DEVICE=$2 ;;
        --branch) BRANCH=$2 ;;
        --source) OPENWRTROOT=$2 ;;
        --jobs) JOBS=$2 ;;
      esac
      shift 2 ;;
    --no-prebuilt) PREBUILT=0; shift ;;
    --dry-run) dry_run=1; shift ;;
    --json) json=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "$command" in
  help|-h|--help) usage; exit 0 ;;
  devices)
    if (( json )); then list_devices | jq -R . | jq -sc .; else list_devices; fi
    exit 0 ;;
  check) exec bash "$REXWRT_ROOT/tests/run.sh" ;;
  plan|clone|feeds|adapt|configure|download|preflight|compile|images|build) ;;
  *) die "Unknown command: $command (see ./rexwrt help)" ;;
esac
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die '--jobs must be a positive integer'
[[ "$BRANCH" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ && "$BRANCH" != *..* && "$BRANCH" != */ ]] || die 'Invalid branch or tag'
if (( dry_run )) && [[ "$command" != adapt ]]; then die '--dry-run is supported by adapt only'; fi
load_device
OPENWRTROOT=${OPENWRTROOT:-$REXWRT_ROOT/work/$DEVICE/${BRANCH//\//-}/openwrt}
[[ "$OPENWRTROOT" = /* ]] || OPENWRTROOT=$PWD/$OPENWRTROOT
export DEVICE BRANCH OPENWRTROOT JOBS PREBUILT

require_source() {
  [[ -f "$OPENWRTROOT/include/toplevel.mk" ]] || die "OpenWrt checkout not found: $OPENWRTROOT"
}
linux_only() { [[ $(uname -s) == Linux ]] || die 'Firmware builds require a Linux host'; }
clone_source() {
  require_command git
  [[ ! -e "$OPENWRTROOT" ]] || die "Source path already exists: $OPENWRTROOT (use the individual stages for an existing checkout)"
  mkdir -p "$(dirname "$OPENWRTROOT")"
  git clone --single-branch --branch "$BRANCH" "${REPO_URL:-https://github.com/openwrt/openwrt}" "$OPENWRTROOT"
}
update_feeds() {
  linux_only
  require_source
  (cd "$OPENWRTROOT" && ./scripts/feeds update -a && ./scripts/feeds install -a)
}
adapt_device() {
  require_source
  if [[ -f "$DEVICE_DIR/apply.sh" ]]; then
    local args=("--openwrt-root=$OPENWRTROOT")
    if (( dry_run )); then args+=(--dry-run); fi
    bash "$DEVICE_DIR/apply.sh" "${args[@]}"
  else
    log "$DEVICE uses upstream device support"
  fi
}
configure_source() {
  linux_only
  require_source
  [[ ! -f "$OPENWRTROOT/.rexwrt-configured" ]] || die 'This checkout is already configured; use a fresh checkout to reconfigure'
  seed_config > "$OPENWRTROOT/.config"
  mkdir -p "$OPENWRTROOT/files"
  cp -R "$REXWRT_ROOT/overlay/." "$OPENWRTROOT/files/"
  # Device support is independent of package customization and always runs first.
  adapt_device
  (
    cd "$OPENWRTROOT"
    bash "$REXWRT_ROOT/scripts/customize/packages.sh"
    bash "$REXWRT_ROOT/scripts/customize/patches.sh"
    bash "$REXWRT_ROOT/scripts/customize/translations.sh"
    bash "$REXWRT_ROOT/scripts/customize/terminal.sh"
    make defconfig
    # A failed package metadata scan must not silently produce a wired-only R28S.
    if [[ "$DEVICE" == nanopi-r28s ]]; then
      for package in kmod-aic8800-sdio aic8800-sdio-firmware kmod-r28s-bluetooth kmod-hci-uart; do
        grep -Eq "^CONFIG_PACKAGE_${package}=[ym]$" .config || die "Required R28S package was dropped by defconfig: $package"
      done
    fi
    if [[ "$PREBUILT" == 1 ]]; then
      bash "$REXWRT_ROOT/tools/external-host-tools.sh"
      bash "$REXWRT_ROOT/tools/external-toolchain.sh"
    fi
    profile=$(grep '^CONFIG_TARGET_.*_DEVICE_.*=y$' "$DEVICE_DIR/config.seed")
    grep -Fx "$profile" .config >/dev/null || die "Selected device profile was dropped by defconfig: $profile"
  )
  printf '%s %s\n' "$DEVICE" "$BRANCH" > "$OPENWRTROOT/.rexwrt-configured"
}
download_source() {
  linux_only; require_source
  (cd "$OPENWRTROOT" && make download -j"$JOBS")
}
compile_source() {
  linux_only; require_source
  local scope=${1:-full}
  # OpenWrt reads V only as a make command-line variable, not from the environment.
  (
    cd "$OPENWRTROOT"
    make tools/compile -j"$JOBS" V="${V:-}"
    for target in toolchain/compile target/compile; do
      make "$target" -j"$JOBS" V="${V:-}"
    done
    # Surface device failures before unrelated Go and container packages start.
    # Individual package targets resolve their dependencies through OpenWrt.
    if [[ "$DEVICE" == nanopi-r28s ]]; then
      for target in package/kernel/aic8800-sdio/compile package/boot/uboot-rexwrt-r28s/compile; do
        make "$target" -j"$JOBS" V="${V:-}"
      done
    fi
    if [[ "$scope" == full ]]; then
      for target in package/compile package/index; do
        make "$target" -j"$JOBS" V="${V:-}"
      done
      make diffconfig V="${V:-}"
    fi
  )
}
generate_images() {
  linux_only; require_source
  (cd "$OPENWRTROOT" && make package/install -j"$JOBS" V="${V:-}" && make target/install -j"$JOBS" V="${V:-}")
  bash "$REXWRT_ROOT/scripts/collect-images.sh"
}

case "$command" in
  plan)
    printf 'Device: %s\nOpenWrt: %s\nTarget: %s/%s\nSource: %s\nJobs: %s\nPrebuilt tools: %s\n' \
      "$DEVICE" "$BRANCH" "$TARGET_BOARD" "$TARGET_SUBTARGET" "$OPENWRTROOT" "$JOBS" "$PREBUILT"
    printf 'Stages: clone -> feeds -> configure -> download -> compile -> images\n'
    ;;
  clone) clone_source ;;
  feeds) update_feeds ;;
  adapt) adapt_device ;;
  configure) configure_source ;;
  download) download_source ;;
  preflight) V=${V:-s} compile_source preflight ;;
  compile) compile_source ;;
  images) generate_images ;;
  build) linux_only; clone_source; update_feeds; configure_source; download_source; compile_source; generate_images ;;
esac
