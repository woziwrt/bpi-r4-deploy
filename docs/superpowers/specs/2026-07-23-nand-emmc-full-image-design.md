# Full router image to NAND and eMMC (BPI-R4-8P PoE, 8 GB)

Date: 2026-07-23
Status: implemented and verified

## Goal

Run the same OpenWrt system that works on the SD card from NAND, then from
eMMC, on a `bananapi,bpi-r4-2g5` (PoE) board with 8 GB RAM. Final boot target:
eMMC. "Same config" means the identical package set *and* the identical `/etc`
customisations, not an approximation.

## Key insight

All targets are built from one local tree, so NAND, eMMC and SD run a
byte-identical squashfs. Config migration therefore reduces to copying the
read-write overlay (~34 MiB) rather than reinstalling packages, and no drift is
possible between the systems.

## Constraints discovered

- **No PoE NAND image existed.** `Device/bananapi_bpi-r4-poe-8gb` built
  `emmc/nvme/sdcard` artifacts only. The `…-nand-8gb-snand-img.bin` published
  even under the `release-8gb-poe` tag is the *non-PoE* lean installer;
  `.github/workflows/build-bpi-r4-deploy.yml` copies the same file into both
  `rel-8gb` and `rel-8gb-poe`. `install-nand.sh` states it: "PoE boards are not
  handled here."
- **The PoE snand U-Boot env was unbootable.** `defenvs/bananapi_bpi-r4-poe_snand_env`
  omitted `mt7988a-bananapi-bpi-r4-spim-nand` from `bootconf_extra`, which its
  non-PoE counterpart has. Every overlay it *does* name exists in the FIT, so
  `bootm` succeeds and the kernel boots — then dies before userspace with no
  SPI-NAND controller in its device tree, so it never finds the UBI rootfs.
  Observed symptom: board powers on, PHY links at 1000/full, no DHCP, no ARP.
  Fixed in `my_files/471-w-bpi-r4-led-uboot.patch`.
  The eMMC path does not share this defect: its `boot_production` uses
  `bootm $loadaddr#$bootconf#$bootconf_emmc#$bootconf_extra`.
- **NAND usable space is 128 MiB, not 256 MiB.**
  `mt7988a-bananapi-bpi-r4-spim-nand.dtso` hardcodes `BL2 @ 0x0 size 0x200000`
  plus `ubi @ 0x200000 size 0x7e00000`; the chip is 256 MiB and half is
  unmapped. Do not estimate NAND overlay space from the chip size.
- **eMMC is invisible under SD boot** (shared MMC controller), so eMMC must be
  installed from the NAND system. This dictates NAND-before-eMMC ordering.
- Serial console is RX-only; recovery depends on the SD card staying bootable.
- No passwordless sudo on the host, so `sshpass`/`expect` are unavailable.

## Actual space budget

UBI totals 122 MiB (1008 LEBs of 124 KiB):

| Volume | With Docker | Docker removed |
|---|---|---|
| `fit` (kernel + rootfs) | 106.5 MiB | ~49 MiB |
| `fip` + `ubootenv` ×2 | 3.2 MiB | 3.2 MiB |
| **`rootfs_data` → /overlay** | **4.1 MiB** | **57.3 MiB** |

The config needs ~34 MiB (33 MiB of it the static `qbittorrent-nox`), so Docker
had to go on NAND. Dropping Docker alone was sufficient — qBittorrent was kept
and the transmission fallback was not needed. eMMC has 7.2 GiB and keeps Docker.

## Implementation

### 1. `Device/bananapi_bpi-r4-poe-nand-8gb` (new)

PoE DTS + PoE FIP + 2.5G PHY packages, Docker deliberately absent. Produces
`snand-img.bin` and a `sysupgrade.itb`. `UBINIZE_PARTS` is overridden after the
`common-8gb` call because that template hardcodes the non-PoE FIP.

### 2. Config bundle

Tar of `/overlay/upper` from the source system, extracted over `/` on the
target. The overlay contains ~38 **whiteouts** (one char device 0,0 plus
hardlinks to it) marking files deleted from the squashfs — mostly spent
`uci-defaults` scripts, but also disabled services. busybox tar cannot
`--exclude`, and excluding the hardlink target breaks the links, so the bundle
is repacked with python `tarfile` dropping char/block/hardlink members and each
recorded path is then `rm -f`'d on the target to let overlayfs create a proper
whiteout.

### 3. NAND

`mtd -e spi0.0 write` from the SD system, readback-verified, then DIP `A=0,B=1`.
Because the first image still carried Docker, the Docker-less build was
delivered afterwards by `sysupgrade` **from the running NAND system**, which
needs no DIP change and resizes the UBI volumes.

### 4. eMMC

`install-emmc.sh` from the NAND system against the prebuilt
`poe-8gb-emmc-img.bin`. Note the script hardcodes the local-file path to
`/tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-emmc-img.bin` regardless of the
variant selected, so a PoE image must be renamed to that for option `[2]`.
The f2fs overlay is formatted on first boot, so there is no filesystem to
pre-seed beforehand — config is restored after the first boot instead.

## Verified result

| | NAND (`A=0,B=1`) | eMMC (`A=1,B=0`) — final | SD (`A=1,B=1`) |
|---|---|---|---|
| Packages vs SD | 538 (−5 Docker) | 543, identical | 543 original |
| Overlay | 57 MiB | 7.1 GB | 58 GB |
| Status | verified spare | verified, live | untouched rollback |

Confirmed on both: board `bananapi,bpi-r4-2g5`, `mtk_2p5ge` PHY loaded,
`br-wan` = poe-wan/sfp-wan/wan, `br-lan` = lan1-3, 4 WiFi interfaces, ksmbd and
dnsmasq running, NVMe mounted, VPN kill switch active, qBittorrent WebUI on
:8080.

With the WAN cable on poe-wan: PPPoE up (`88.159.163.105`), DNS resolving,
WireGuard tunnel established, qBittorrent egressing `186.247.164.175` (Nord
exit) while the router egresses the ISP IP, no IPv6 leak, and `ifdown nordvpn`
cuts uid 225 while the router stays online. The kill switch trips at the
**ip-rule** layer (prio 91 `unreachable`), so the nft `skuid` drop counter reads
0 even while actively blocking.

Testing gotcha: this busybox has no `su` applet. Use
`start-stop-daemon -S -c qbittorrent -x /usr/bin/wget -- …` to test as uid 225;
a bare `su` fails silently and is indistinguishable from a blocked network.

## Rollback

DIP `A=0,B=1` for NAND, `A=1,B=1` for the original SD system. The SD card and
the NVMe data partition were never written.
