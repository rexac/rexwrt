# R28S dynamic adaptation

## Source policy

Each fresh adaptation resolves moving branches once and records the exact commits.
There is no dependency on an unmerged OpenWrt PR or a personal fork.

| Component | Source |
| --- | --- |
| Board devicetree | Linux mainline |
| Bootloader | Official U-Boot `main`, falling back to official `next` while R28S is absent from `main` |
| DDR and BL31 firmware | Official Rockchip rkbin; names and revision selected together by the latest OpenWrt package |
| Wireless integration | Armbian's current R28S configuration |
| SDIO Wi-Fi driver and firmware | Radxa's current AIC8800 source and SDIO compatibility patch series |
| UART Bluetooth protocol | Armbian's selected Rockchip vendor-kernel branch |

U-Boot initializes and starts Linux; it does not replace Linux wireless drivers.
R28S uses AIC8800D80 with SDIO Wi-Fi and UART2 Bluetooth. Armbian's UART protocol
requests the SDIO module to load the Bluetooth firmware, so both pieces are needed.

## Build behavior

The selected OpenWrt stable or snapshot kernel is retained. The adapter reconstructs
affected files from that exact kernel release and OpenWrt's existing patch queues,
then generates the board and Bluetooth changes. Wireless API guards use the
OpenWrt cfg80211 backport version; core-kernel API guards keep the kernel version.
The Bluetooth H4 receive argument follows the reconstructed kernel header.
Missing shared driver API declarations are added to their headers. Remaining vendor
`missing-prototypes` diagnostics stay visible as warnings within the AIC8800 package;
other compiler errors remain fatal.
Unknown layouts or patch conflicts stop adaptation before modifying the checkout.
Configuration also stops if required Wi-Fi or UART Bluetooth packages are dropped
by `defconfig`.

An existing OpenWrt R28S profile and its bootloader selection are retained. Otherwise,
a separate package builds official U-Boot without replacing the shared Rockchip
bootloader package. Its configuration loads OpenWrt's `boot.scr` from microSD/eMMC.

All changes are staged in a temporary directory and checked together. `adapt
--dry-run` validates them without writing into the OpenWrt checkout. A checkout is
adapted once; start from a fresh checkout to resolve newer branch heads.

## Reproduction and checks

Fresh R28S installations prepare `wwan` and `wwan6` for a wireless uplink;
select the upstream SSID and credentials in LuCI. IPv6 RA, DHCPv6 and NDP
relay support the verified REX uplink, which supplies an on-link /64 without
prefix delegation. `extendprefix` is disabled. A hotplug hook selects the
uplink's global source address for router-originated IPv6 traffic and removes
the fallback default route when `wwan6` goes down. This relay configuration
is intended for that upstream topology; routed prefix delegation requires
LAN RA/DHCPv6 server mode instead. Restored network settings are preserved.

Hardware validation on November 21, 2026 confirmed that DOORLINK, the REX
station, LAN client IPv6 and Tailscale IPv6 recovered after a reboot. IPv6
became available after the upstream router advertisement arrived.

An IPv4 policy rule at priority 5260 prefers non-default routes in the main
table before Tailscale's subnet routes. This keeps LuCI accessible through
the wireless uplink when an accepted Tailscale subnet overlaps the local
network. The rule also applies when restoring earlier R28S network settings.

Source revisions, the exact kernel release, input hashes and a replay bundle are
saved under `OPENWRT/.rexwrt/r28s/`. Revisions are copied to the build output
directory but are not uploaded to GitHub Releases.
To replay discovered inputs, set `REXWRT_R28S_SOURCES` to that checkout's
`.rexwrt/r28s/upstream` directory. Immutable kernel files are cached under
`work/upstream-cache/`; override this with `REXWRT_UPSTREAM_CACHE`.

`./rexwrt check` runs offline tests. `tests/r28s-integration.sh` replays the adapter
against stable and snapshot archives with a supplied source bundle and kernel
cache. These checks cover generation and application, not successful booting or
radio operation. Firmware compilation and hardware validation must be reported
separately; eMMC, Wi-Fi and Bluetooth remain experimental until tested on a board.
