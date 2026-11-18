# R28S dynamic adaptation

## Source policy

Each fresh adaptation resolves moving branches once and records the exact commits.
There is no dependency on an unmerged OpenWrt PR or a personal fork.

| Component | Source |
| --- | --- |
| Board devicetree | Linux mainline |
| Bootloader | Official U-Boot `main`, falling back to official `next` while R28S is absent from `main` |
| DDR and BL31 firmware | Official Rockchip rkbin; names and revision selected together by the latest OpenWrt package |
| Wireless integration | Latest FriendlyWrt release manifest and its selected RK3528 build scripts |
| SDIO Wi-Fi driver and firmware | Official `friendlyarm/aic8800` moving `main` branch, installed under `/lib/firmware/aic` |
| UART Bluetooth protocol and node | Official `friendlyarm/kernel-rockchip` branch selected by that manifest |

U-Boot initializes and starts Linux; it does not replace Linux wireless drivers.
R28S uses AIC8800D80 with SDIO Wi-Fi and UART2 Bluetooth. FriendlyElec's UART protocol
requests the SDIO module to load the Bluetooth firmware, so both pieces are needed.

## Build behavior

The selected OpenWrt stable or snapshot kernel is retained. The adapter reconstructs
affected files from that exact kernel release and OpenWrt's existing patch queues,
then generates the board and Bluetooth changes. Wireless API guards use the
OpenWrt cfg80211 backport version; core-kernel API guards keep the kernel version.
Driver configuration reads the staged cfg80211 callbacks and target kernel headers
to adapt radio arguments, timer calls and module namespace syntax independently.
Unknown board layouts or kernel patch conflicts stop adaptation before modifying the checkout.

An existing OpenWrt R28S profile and its bootloader selection are retained. Otherwise,
a separate package builds official U-Boot without replacing the shared Rockchip
bootloader package. Its configuration loads OpenWrt's `boot.scr` from microSD/eMMC.

All changes are staged in a temporary directory and checked together. `adapt
--dry-run` validates them without writing into the OpenWrt checkout. A checkout is
adapted once; start from a fresh checkout to resolve newer branch heads.

## Reproduction and checks

Source revisions, the exact kernel release, input hashes and a replay bundle are
saved under `OPENWRT/.rexwrt/r28s/`. Revisions are also installed under
`/etc/rexwrt/` in the firmware and copied beside collected release images.
To replay discovered inputs, set `REXWRT_R28S_SOURCES` to that checkout's
`.rexwrt/r28s/upstream` directory. Immutable kernel files are cached under
`work/upstream-cache/`; override this with `REXWRT_UPSTREAM_CACHE`.

`./rexwrt check` runs offline tests. `tests/r28s-integration.sh` replays the adapter
against stable and snapshot archives with a supplied source bundle and kernel
cache. These checks cover generation and application, not successful booting or
radio operation. Firmware compilation and hardware validation must be reported
separately; eMMC, Wi-Fi and Bluetooth remain experimental until tested on a board.
