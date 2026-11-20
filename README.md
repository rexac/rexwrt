# rexwrt

Customized OpenWrt builds for `nanopi-neo2-black`, `nanopi-r28s`, and `x86-64`.
Default LAN IP: `192.168.5.1` on R28S; `10.0.0.1` on other devices.
NEO2 Black board patches are generated from Armbian for the detected kernel and U-Boot versions; its CPU info patch is generated from the matching Linux source.
Go build recipes follow official OpenWrt `packages/master` on both stable and snapshot builds.

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
Device and release dropdowns are generated from `./rexwrt devices` and the five
latest official stable tags. **Sync build choices** updates them daily, on device
changes, or manually, using the existing `SEC_TOKEN` with contents and workflow
write access. Select `custom` to enter another OpenWrt branch or tag.
Use `mode: preflight` to compile only the kernel and device packages with verbose logs.
Full builds run this check first; a compiler cache (up to 1 GB per entry) is saved even after failures.
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
Resolved R28S revisions are copied beside release images.
On first boot, `90-r28s-network` applies R28S network, wireless, and firewall
settings while keeping OpenWrt's DHCP and DNS defaults.
Connect to `DOORLINK` (default key: `abcd1234`) to reach `192.168.5.1`;
both Ethernet ports belong to the `doorlink` bridge. Flash without keeping
settings to use these defaults on an existing installation.

This adaptation is experimental; full firmware and hardware validation, including
Wi-Fi, Bluetooth and eMMC boot, must be checked separately. Start with microSD.
