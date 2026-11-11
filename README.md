# OpenWrt + UniFi Stack for Banana Pi BPI-R4 & BPI-R4 Pro 8X

Run **OpenWrt** on Banana Pi BPI-R4 and **BPI-R4 Pro 8X** (MT7988A, Wi-Fi 7) with an optional **UniFi Protect + UniFi Network Application** stack — a cost-effective alternative to the Ubiquiti UNVR + Cloud Gateway combo.

Ready-made images are in [Releases](https://github.com/woziwrt/bpi-r4-deploy/releases); the installer scripts download them for you. Everything is built on GitHub — no Linux machine needed, not even to build your own fork.

> **Tested hardware:** Banana Pi R4 rev 1.0 (4GB) · Banana Pi R4 rev 1.1 (8GB) · Banana Pi R4 Pro 8X · UniFi G5 Flex camera · UniFi U7-LR WiFi 7 AP

---

## Contents

- [Quick start: which image do I need?](#quick-start-which-image-do-i-need)
- [What is in the image](#what-is-in-the-image)
- [DIP switch reference](#dip-switch-reference)
- [Part A — BPI-R4: Install](#part-a--bpi-r4-install)
- [Part B — BPI-R4: UniFi stack](#part-b--bpi-r4-unifi-stack)
- [Part C — BPI-R4 Pro 8X: Install](#part-c--bpi-r4-pro-8x-install)
- [Part D — BPI-R4 Pro 8X: UniFi stack](#part-d--bpi-r4-pro-8x-unifi-stack)
- [Updating](#updating)
- [Part E — Fork and customize](#part-e--fork-and-customize)
- [NVMe partition layout](#nvme-partition-layout)
- [Hardware notes](#hardware-notes)
- [Known behaviors](#known-behaviors)
- [Reporting a problem](#reporting-a-problem)

---

## Quick start: which image do I need?

**Standard** = with the on-board/PCIe Wi-Fi 7 card. **Wired** = without Wi-Fi (smaller image, for a router or a UniFi server with a separate AP).

### BPI-R4

| Your board | Wi-Fi | Release |
|---|---|---|
| 4 GB | ✅ | `release-4gb-standard` |
| 4 GB | ❌ | `release-4gb-wired` |
| 4 GB with 2.5GE PoE port | ✅ | `release-4gb-poe` |
| 4 GB with 2.5GE PoE port | ❌ | `release-4gb-poe-wired` |
| 8 GB | ✅ | `release-8gb-standard` |
| 8 GB | ❌ | `release-8gb-wired` |
| 8 GB with 2.5GE PoE port | ✅ | `release-8gb-poe` |
| 8 GB with 2.5GE PoE port | ❌ | `release-8gb-poe-wired` |
| 8 GB, UniFi server | ❌ | `release-8gb-wired-unifi` (installed by `install-nvme-unifi.sh`, see [Part B](#part-b--bpi-r4-unifi-stack)) |
| 8 GB PoE, UniFi server | ❌ | `release-8gb-poe-wired-unifi` (same) |

> ⚠️ **The UniFi stack needs 8 GB RAM and an NVMe SSD.** UniFi Network + Protect exhaust 4 GB of RAM.

### BPI-R4 Pro 8X

| Wi-Fi | Release |
|---|---|
| ✅ | `release-pro-8x-standard` |
| ❌ | `release-pro-8x-wired` |

Pro 8X images do **not** work on the BPI-R4 and the other way round.

### What a release contains

| File | Used for |
|---|---|
| `…-sdcard.img.gz` | microSD card — flash with Etcher, boots on its own ([Step 1](#step-1--flash-the-sd-card)) |
| `…-snand-img.bin` | NAND installer system, written by `install-nand.sh` |
| `…-emmc-img.bin` | eMMC, written by `install-emmc.sh` |
| `…-nvme-img.bin` + `bpi-r4*.itb` | NVMe, written by `install-nvme.sh` |
| `bpi-r4*.itb` | firmware update with `sysupgrade` ([Updating](#updating)) |
| `sha256sums`, `config.buildinfo` | checksums and the exact build configuration |

You normally download only the SD image by hand; the installers fetch the rest.

---

## What is in the image

- OpenWrt 25.12 with Linux 6.12, plus the MediaTek MT7988A feed (Ethernet, SFP, 10G PHYs).
- The MediaTek Wi-Fi 7 stack (mt76, mac80211, hostapd) in the standard variants.
- LuCI, Docker, modem tools (`sms-tool`, LuCI apps for modem data, SMS and a connection watchdog) and, in the standard variants, `luci-app-wifimgr`.

The exact upstream revisions are in [`pins.conf`](pins.conf); every image is built from those.

After installation the router is at **`192.168.1.1`**, user `root`, **no password** — set one first (LuCI → System → Administration, or `passwd`).

---

## DIP switch reference

| Boot medium | A | B |
|-------------|---|---|
| SD card     | 1 | 1 |
| NAND        | 0 | 1 |
| eMMC        | 1 | 0 |

> **NVMe boot** is controlled by the U-Boot environment, not by the DIP switch. After `install-nvme.sh` the board boots from NVMe automatically — the DIP stays at **NAND** (A=0, B=1) and is never changed again.

NAND and eMMC are fully working permanent options. NVMe is recommended for larger storage and is required for the UniFi stack.

---

## Part A — BPI-R4: Install

The SD card is a **full, self-contained OpenWrt system**. It boots on its own and
ships the installer scripts in `/root/install-dir/`. From there you write a small
installer system to NAND, and the NAND system installs eMMC or NVMe.

> **Why go through NAND?** eMMC and the SD card share the same MMC controller, so
> eMMC cannot be written while you are booted from SD. Installing eMMC (and, for a
> consistent flow, NVMe) is therefore always done from the NAND system.

If you only want to try OpenWrt, Step 1 is enough — run it from the SD card.

### Step 1 — Flash the SD card

1. In [Releases](https://github.com/woziwrt/bpi-r4-deploy/releases) open the release for your board
   ([which one?](#quick-start-which-image-do-i-need)) and download its **SD image**, for example:

   | RAM | Release | SD image |
   |---|---|---|
   | 4 GB | `release-4gb-standard` | `openwrt-mediatek-filogic-bananapi_bpi-r4-sdcard.img.gz` |
   | 8 GB | `release-8gb-standard` | `openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-sdcard.img.gz` |

   PoE boards use the `release-*-poe` releases and the `…-poe-…-sdcard.img.gz` image.

2. Flash it to a microSD card with [Balena Etcher](https://etcher.balena.io/).
3. Insert the SD card, set DIP **A=1, B=1** (SD boot) and power on.
4. Connect via SSH: `ssh root@192.168.1.1` (no password).

---

### Step 2 — Write the NAND installer system

Connect the WAN cable and run from the SD card:

```
/root/install-dir/install-nand.sh
```

Select your **RAM (4 GB or 8 GB)**, then the file source — download from GitHub (default) or a local file in `/tmp`.
The board is detected from the running system: a **2.5GE PoE** board (booted from the PoE SD image) gets the PoE NAND image, with the PoE U-Boot.

> ⚠️ **PoE boards:** the PoE NAND image and the NVMe boot from it are not tested on hardware — we do not own a PoE board.
> If you install it, please report how it went in an [issue](https://github.com/woziwrt/bpi-r4-deploy/issues).

After the script finishes:

1. Power off.
2. Set DIP **A=0, B=1** (NAND boot) and power on.
3. Connect via SSH: `ssh root@192.168.1.1`.

You are now on the NAND system, which installs eMMC and NVMe below.

---

### Step 3 — Install OpenWrt to NVMe

> Run this **from the NAND system** (DIP A=0, B=1).

> ⚠️ **Want both NVMe and eMMC?** Run `install-emmc.sh` **before** `install-nvme.sh`. After the NVMe installation the board always boots from NVMe.

> For the **UniFi stack** use `install-nvme-unifi.sh` instead — see [Part B](#part-b--bpi-r4-unifi-stack).

Connect the WAN cable and run:

```
/root/install-dir/install-nvme.sh
```

Select your board variant (1–8). The script checks the NVMe health, downloads the images (~150 MB), **erases the whole NVMe**, writes OpenWrt and reboots into it.

---

### Step 3 alternative — Install to eMMC

> Run this **from the NAND system** (DIP A=0, B=1). eMMC shares its controller
> with the SD card, so it cannot be written from the SD system.

```
/root/install-dir/install-emmc.sh
```

Select your board variant (1–8). After the installation set DIP **A=1, B=0** (eMMC boot) and power on.

---

## Part B — BPI-R4: UniFi stack

### What you need

- BPI-R4 **8 GB RAM** (rev 1.2+ recommended, see [Hardware notes](#hardware-notes))
- NVMe SSD, minimum 500 GB (1 TB recommended for continuous recording)
- UniFi camera (G5 Flex tested) · UniFi AP (U7-LR WiFi 7 tested)
- A [Ubiquiti account](https://account.ui.com) (optional — only for Remote Access)

When everything is set up:

| Service | Address |
|---------|---------|
| UniFi Protect | `https://192.168.1.1` |
| UniFi Network Application | `https://192.168.1.2:8443` |
| LuCI | `http://192.168.1.1:8081` |

---

### Step 1 — Install the UniFi NVMe system

Do [Part A](#part-a--bpi-r4-install) Steps 1–2, then from the NAND system, with the WAN cable connected:

```
/root/install-dir/install-nvme-unifi.sh
```

1. Select **1** (8 GB wired UniFi) or **2** (8 GB PoE wired UniFi).
2. Select the disk profile: **1** for a production disk (1 TB+, 30 GB data partition) or **2** for a small test disk (128 GB, 15 GB data partition). The rest of the disk is for recordings.

The script erases the whole NVMe, installs OpenWrt, puts the UniFi setup scripts on the data partition and reboots.

---

### Step 2 — Set up UniFi Protect

> ⚠️ **Run this from an SSH terminal, not from the LuCI terminal (ttyd).** The script changes the firewall and moves LuCI to another port, which cuts a ttyd session.

```
cd /mnt/nvme0n1p3
sh unifi-setup.sh
```

When asked, choose **[1] Download** — the script downloads the Protect Docker image (~660 MB) and loads it.

> ⚠️ When prompted, **disconnect the WAN cable** before pressing Enter.

---

### Step 3 — First-time Protect configuration

1. Open `https://192.168.1.1`.
2. Accept the SSL warning (self-signed certificate).
3. **Other Configuration Options → Local Network → Set Up Console Offline**.
4. Enter a console name, set a password, click **Finish**.

**Immediately disable auto-updates: Settings → Control Plane → Updates.** An automatic Protect update can break the stack.

---

### Step 4 — Set up the UniFi Network Application

Reconnect the WAN cable, then:

```
cd /mnt/nvme0n1p3
sh unifi-network-setup.sh
```

---

### Step 5 — First-time Network Application configuration

1. Open `https://192.168.1.2:8443`.
2. Complete the setup wizard.
3. **Settings → System** — disable auto-updates.

---

### Adding a camera

1. Connect the camera to a LAN port and power it on.
2. Hardware reset (hold the reset button until the LED changes).
3. Protect dashboard → **Devices** — the camera appears for adoption.

---

### Adopting an Access Point

After a factory reset the AP finds the Network Application through DNS (`unifi` → `192.168.1.2`). It appears as "Pending adoption" within a minute.

If auto-discovery fails (older AP firmware):

```
ssh ubnt@<AP_IP> "/usr/bin/syswrapper.sh set-inform http://192.168.1.2:8080/inform"
```

`<AP_IP>` is shown in LuCI (`http://192.168.1.1:8081`) → Network → DHCP Leases. Default AP credentials: `ubnt` / `ubnt`.

---

## Part C — BPI-R4 Pro 8X: Install

The BPI-R4 Pro 8X has a different NAND layout and device trees than the standard BPI-R4. **Pro 8X images are not compatible with the standard BPI-R4 and vice versa.**

### What you need

- BPI-R4 Pro 8X board
- **NVMe SSD in slot CN14 (M-key), minimum 512 GB** — tested with Patriot P300 512 GB. CN15 and CN18 are B-key slots for LTE modems, not for NVMe.
- microSD card (temporary, for the installation only)
- For WAN and LAN: SFP or SFP copper modules are recommended

---

### Step 1 — Flash the SD card

1. In [Releases](https://github.com/woziwrt/bpi-r4-deploy/releases) open **release-pro-8x-standard** (Wi-Fi) or **release-pro-8x-wired** and download
   `openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-sdcard.img.gz`.
2. Flash it to a microSD card with [Balena Etcher](https://etcher.balena.io/).
3. Insert the SD card, set DIP **A=1, B=1** (SD boot) and power on.
4. Connect via SSH: `ssh root@192.168.1.1` (no password).

---

### Step 2 — Install the NAND system

Connect the WAN cable, then run:

```
/root/install-dir/install-nand.sh
```

Select **1** (standard, Wi-Fi 7) or **2** (wired). After the script finishes:

1. Power off.
2. Set DIP **A=0, B=1** (NAND boot) and power on.
3. Connect via SSH: `ssh root@192.168.1.1`.

---

### Step 3 — Optional: Install to eMMC

> ⚠️ **Run this before `install-nvme.sh`.** After the NVMe installation the board always boots from NVMe.

```
/root/install-dir/install-emmc.sh
```

Select **1** (Pro 8X Wi-Fi) or **2** (Pro 8X wired).

After the installation set DIP **A=1, B=0** (eMMC boot) to use eMMC, or keep DIP at A=0, B=1 and continue with the NVMe install.

---

### Step 4 — Install OpenWrt to NVMe

> For the **UniFi stack** use `install-nvme-unifi.sh` instead — see [Part D](#part-d--bpi-r4-pro-8x-unifi-stack).

From the NAND system, connect the WAN cable and run:

```
/root/install-dir/install-nvme.sh
```

Select **1** (Pro 8X Wi-Fi) or **2** (Pro 8X wired).

The script checks the NVMe health, downloads the images (~150 MB), **erases the whole NVMe**, writes OpenWrt and reboots.

**After the reboot the router runs from NVMe.** The DIP stays at A=0, B=1 for good — this is correct.

---

### Switching between NAND and NVMe

```
boot-nand    # switch to NAND on next reboot
boot-nvme    # switch back to NVMe on next reboot (run it on the NAND system)
```

---

## Part D — BPI-R4 Pro 8X: UniFi stack

The Pro 8X wired variant is well suited for the UniFi stack — 8 GB RAM, NVMe storage and no on-board Wi-Fi.

### What you need

- BPI-R4 Pro 8X (wired variant recommended)
- NVMe SSD in slot CN14, **minimum 512 GB** (1 TB recommended for continuous recording)
- UniFi camera (G5 Flex tested) · UniFi AP (U7-LR WiFi 7 tested)
- A [Ubiquiti account](https://account.ui.com) (optional — only for Remote Access)

When everything is set up:

| Service | Address |
|---------|---------|
| UniFi Protect | `https://192.168.1.1` |
| UniFi Network Application | `https://192.168.1.2:8443` |
| LuCI | `http://192.168.1.1:8081` |

### Steps

1. Do [Part C](#part-c--bpi-r4-pro-8x-install) Steps 1–2, then from the NAND system, with the WAN cable connected:
   ```
   /root/install-dir/install-nvme-unifi.sh
   ```
   Select **1** (Pro 8X Wi-Fi) or **2** (Pro 8X wired), then the disk profile (**1** production 1 TB+, **2** test 128 GB).
2. Set up Protect (SSH terminal only, not ttyd): `sh /mnt/nvme0n1p3/unifi-setup.sh` — choose **[1] Download**, and **disconnect the WAN cable** when prompted.
3. First-time Protect configuration — same as [Part B Step 3](#step-3--first-time-protect-configuration). Disable auto-updates in **Settings → General → Auto Update**.
4. Reconnect the WAN cable and set up the Network Application: `sh /mnt/nvme0n1p3/unifi-network-setup.sh`
5. Open `https://192.168.1.2:8443`, complete the wizard, disable auto-updates in **Settings → System**.

Cameras and access points are adopted as in Part B — see [Adding a camera](#adding-a-camera) and [Adopting an Access Point](#adopting-an-access-point).

---

## Updating

Update a running system with the release's `.itb` file (`bpi-r4.itb`, `bpi-r4-poe.itb` or `bpi-r4-pro-8x.itb`):

- **LuCI** → System → Backup / Flash Firmware → *Flash image*, keep settings ticked, or
- **SSH:** copy the file to `/tmp` and run `sysupgrade /tmp/bpi-r4.itb`.

What survives depends on where the system runs:

| Installed on | Settings | Data partitions |
|---|---|---|
| SD card, eMMC, NAND | kept (standard OpenWrt upgrade) | — |
| NVMe | **not kept** — back to defaults | `p3` (and `p4` on UniFi installs) untouched |

On NVMe the upgrade script writes the new firmware but does not carry the settings over, even with *keep settings* ticked. So before upgrading an NVMe install, save your settings (*System → Backup / Flash Firmware → Generate archive*) and restore that archive after the upgrade.

This table comes from reading the upgrade scripts, not from a test on every board. If your result differs, please open an issue.

> ⚠️ **Do not re-run `install-nvme.sh`, `install-nvme-unifi.sh` or `install-emmc.sh` to update.** They are installers: they erase the whole disk, data partitions included.

---

## Part E — Fork and customize

Fork this repository to build your own releases.

1. Fork on GitHub. **Keep the name `bpi-r4-deploy`** — the installers expect it.
2. **Settings → Actions → General** → set **Workflow permissions** to **Read and write**.
3. **Actions** → pick the workflow for your board → **Run workflow** from `main`:
   - **BPI-R4** — *Build BPI-R4 Deploy*, variant **standard** or **wired**
   - **BPI-R4 Pro 8X** — *Build BPI-R4 Pro 8X*, variant **Pro-8X-wifi** or **Pro-8X-wired**
   - Tick **publish** to turn the build into releases. Unticked, the images are only kept for 14 days as a workflow artifact (handy for testing).
4. After about 2–3 hours the releases appear in your fork.

To install from your fork, choose **"My fork"** when an installer asks where to download from and enter your GitHub username.
The Pro 8X `install-nand.sh`, `install-emmc.sh` and `install-nvme.sh` do not ask yet — change `GH_USER` at the top of those scripts in your fork.

### Repository layout

Both boards are built by one script:

```
./build.sh <bpi-r4|bpi-r4-pro-8x> <standard|wired>
```

| Path | What it holds |
|------|---------------|
| `pins.conf` | Every upstream revision: OpenWrt, MediaTek feed, mt76/mac80211/hostapd/iw/wifi-scripts |
| `build.sh` | The build, step by step |
| `scripts/common.sh` | Build steps shared by both boards |
| `common/` | Patches, packages and image files both boards use |
| `boards/<board>/board.sh` | What only that board does |
| `boards/<board>/` | Its patches, `filogic.mk`, U-Boot/TF-A Makefiles, image files (`files/`, installers in `files/root/install-dir/`), `configs/<variant>.config`, UniFi scripts (`unifi/`) |

To change what is in the image, edit `boards/<board>/configs/<variant>.config`; to add files to the image, put them under `common/files/` (both boards) or `boards/<board>/files/`.

### Building locally

`build.sh` clones OpenWrt and the MediaTek feed itself at the commits in `pins.conf`
(a variable set in the environment wins, e.g. `MTK_COMMIT=<sha>`). On Ubuntu 22.04
with the [OpenWrt build prerequisites](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem):

```
git clone https://github.com/woziwrt/bpi-r4-deploy
cd bpi-r4-deploy
./build.sh bpi-r4-pro-8x standard
```

The images end up in `openwrt/bin/targets/mediatek/filogic/`.

Each run resets and cleans the source checkouts. Local changes in `openwrt` and `mtk-openwrt-feeds` are discarded.
Downloaded source archives in `openwrt/dl/` are kept and reused on subsequent runs.

---

## Architecture

| Component | Role |
|-----------|------|
| BPI-R4 / Pro 8X | Routing, firewall, Docker runtime, NVMe storage |
| UniFi Protect | Camera management ([dciancu](https://github.com/dciancu/unifi-protect-unvr-docker-arm64) Docker image) |
| UniFi Network Application | Wi-Fi management (linuxserver Docker image) |
| UniFi AP | Professional Wi-Fi (U7-LR WiFi 7 tested) |

---

## NVMe partition layout

`install-nvme.sh`:

| Partition | Size | Purpose |
|-----------|------|---------|
| p1 | 256 MB | Boot (kernel) |
| p2 | 16 GB | System (firmware + settings) |
| p3 | rest of the disk | Data (`/mnt/nvme0n1p3`, ext4) |

`install-nvme-unifi.sh`:

| Partition | Size | Purpose |
|-----------|------|---------|
| p1 | 256 MB | Boot (kernel) |
| p2 | 512 MB | System (firmware + settings) |
| p3 | 30 GB (15 GB on the test profile) | Data: UniFi setup, Docker, Network Application |
| p4 | rest of the disk | UniFi Protect recordings (`/mnt/nvme0n1p4`) |

---

## Hardware notes

### BPI-R4 rev 1.0 known issues

| Issue | Details |
|-------|---------|
| NVMe + SFP conflict | Some NVMe disks pull down the I2C bus, disabling the SFP ports |
| Affected disks | Chinese OEM NVMe drives (e.g. generic 128 GB) |
| Not affected | Samsung EVO series |
| Fixed in | Rev 1.2+ |

For new builds, a **BPI-R4 8 GB RAM rev 1.2+** is recommended.

---

## Known behaviors

### Boot time

- ~1 min — router reachable via SSH and LuCI
- ~3 min — UniFi Protect available
- ~8–10 min — UniFi Network Application fully initialized

### WAN reconnect

When WAN goes down and comes back up, the hotplug handler (`99-docker-nft`) restores the Docker nftables rules automatically — no reboot needed.

### NAND first boot — UBI messages

On the very first boot into the NAND system, U-Boot may print messages like:

```
UBI: Bad EC magic in block XXXX
```

This is normal — U-Boot is initializing the NAND flash. The messages disappear on later boots.

### GitHub runner disk space

If a build fails with a disk-related error, re-run the workflow — runners with enough space are usually available shortly.

---

## Reporting a problem

Please open an [issue](https://github.com/woziwrt/bpi-r4-deploy/issues) with:

1. **Board:** BPI-R4 4 GB / 8 GB / PoE, revision, or BPI-R4 Pro 8X.
2. **Release** you installed (e.g. `release-8gb-standard`) and its date, or your fork and commit.
3. **Boot medium:** SD, NAND, eMMC or NVMe.
4. What you did, what you expected and what happened instead.
5. The output of `logread` and `dmesg`, or the serial console log if the board does not boot.

Problems with images built from a modified fork are hard for us to reproduce — please first check whether the same happens with our release.

---

<img width="1264" height="1080" alt="UniFi Protect dashboard" src="https://github.com/user-attachments/assets/1483d00f-839a-4ced-b899-6d688e0483a7" />

<img width="1264" height="1080" alt="UniFi Network Application" src="https://github.com/user-attachments/assets/f912c22e-a31c-42e6-8fc7-34e1632a8bc7" />

<img width="1264" height="1080" alt="LuCI dashboard" src="https://github.com/user-attachments/assets/ae709b45-ad2a-44ff-ab7b-73b9d5f1d6d9" />

<img width="1264" height="1080" alt="UniFi camera view" src="https://github.com/user-attachments/assets/b6ce49af-bd91-4a67-87b2-c77ee121f051" />

---

*This project is not affiliated with Ubiquiti Inc. in any way.*

*🍌 TEAM WOZIWRT+CLAUDE*
