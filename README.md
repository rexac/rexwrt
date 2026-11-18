# rexwrt

Customized OpenWrt builds for `nanopi-neo2-black`, `nanopi-r28s`, and `x86-64`.
Default LAN IP: `10.0.0.1`.
NEO2 Black board patches are generated from Armbian for the detected kernel and U-Boot versions; its CPU info patch is generated from the matching Linux source.

## Build

Requires Linux (Ubuntu 22.04/24.04).

```sh
bash ci/setup.sh

# Snapshot
./rexwrt build --device nanopi-r28s --branch main

# Stable release
./rexwrt build --device nanopi-r28s --branch v25.12.6
```

Firmware and SHA-256 checksums are saved to `release/DEVICE/VERSION/`.
Use `--no-prebuilt` to build tools and the toolchain from source.
Run `./rexwrt help` for commands and options, or `./rexwrt check` for offline checks.

## GitHub Actions

Run **Build** with a device name and OpenWrt branch/tag.
**Repo Dispatcher** triggers both snapshot and the latest stable release for each device;
it requires the `SEC_TOKEN` repository secret with dispatch permission.
**Cleanup workflow runs** uses GitHub's automatic token; no extra secrets are needed.
It runs daily, deleting completed runs older than 7 days
while keeping at least the latest 20 runs per workflow. It also supports manual dry runs.

## NanoPi R28S

Stable and snapshot use generated patches for the selected OpenWrt kernel.
Each fresh build resolves current Linux, U-Boot, Armbian and Radxa branches;
U-Boot prefers official `main`, then official `next` when R28S support is missing.
Wireless integration follows Armbian's AIC8800D80 SDIO/UART setup.
Resolved revisions are embedded in the firmware and copied beside release images.

This adaptation is experimental; full firmware and hardware validation, including
Wi-Fi, Bluetooth and eMMC boot, must be checked separately. Start with microSD.
