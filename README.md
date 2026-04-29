# OpenWrt + UniFi Stack for Banana Pi BPI-R4

Run **OpenWrt** on Banana Pi BPI-R4 (MT7988A, Wi-Fi 7) with an optional **UniFi Protect + UniFi Network Application** stack — a cost-effective alternative to the Ubiquiti UNVR + Cloud Gateway combo.

Complete install system that runs entirely on GitHub — no Linux machine needed.

> **Tested hardware:** Banana Pi R4 rev 1.0 (4GB) · Banana Pi R4 rev 1.1 (8GB) · UniFi G5 Flex camera · UniFi U7-LR WiFi 7 AP

---

## Contents

- [Board variants](#board-variants)
- [What you get](#what-you-get)
- [DIP switch reference](#dip-switch-reference)
- [Part A — Install from ready-made release](#part-a--install-from-ready-made-release)
  - [Step 1 — Flash rescue SD card](#step-1--flash-rescue-sd-card)
  - [Step 2 — Install NAND rescue system](#step-2--install-nand-rescue-system)
  - [Step 3 — Install OpenWrt to NVMe](#step-3--install-openwrt-to-nvme)
  - [Step 3 alternative — Install to eMMC](#step-3-alternative--install-to-emmc)
  - [Sysupgrade](#sysupgrade)
- [Part B — UniFi stack setup](#part-b--unifi-stack-setup)
  - [What you need](#what-you-need)
  - [Step 4 — Install NVMe UniFi variant](#step-4--install-nvme-unifi-variant)
  - [Step 5 — Run UniFi Protect setup](#step-5--run-unifi-protect-setup)
  - [Step 6 — First-time Protect configuration](#step-6--first-time-protect-configuration)
  - [Step 7 — Run UniFi Network Application setup](#step-7--run-unifi-network-application-setup)
  - [Step 8 — First-time Network Application configuration](#step-8--first-time-network-application-configuration)
  - [Adding a camera](#adding-a-camera)
  - [Adopting an Access Point](#adopting-an-access-point)
- [Part C — Fork and customize](#part-c--fork-and-customize)
- [Architecture](#architecture)
- [NVMe partition layout](#nvme-partition-layout)
- [Hardware notes](#hardware-notes)
- [Known behaviors](#known-behaviors)
- [Repository contents](#repository-contents)

---

## Board variants

| # | Variant | RAM | WiFi | Notes |
|---|---------|-----|------|-------|
| 1 | 4GB standard | 4 GB | ✅ | Standard board |
| 2 | 4GB wired | 4 GB | ❌ | No WiFi, lower footprint |
| 3 | 4GB PoE | 4 GB | ✅ | BPI-R4 with 2.5GE PoE port |
| 4 | 4GB PoE wired | 4 GB | ❌ | PoE, no WiFi |
| 5 | 8GB standard | 8 GB | ✅ | 8 GB RAM board |
| 6 | 8GB wired | 8 GB | ❌ | 8 GB RAM, no WiFi |
| 7 | 8GB PoE | 8 GB | ✅ | 8 GB RAM, PoE |
| 8 | 8GB PoE wired | 8 GB | ❌ | 8 GB RAM, PoE, no WiFi |
| 9 | 8GB wired UniFi | 8 GB | ❌ | Pre-configured for UniFi Network + Protect |
| 10 | 8GB PoE wired UniFi | 8 GB | ❌ | PoE, pre-configured for UniFi |

> ⚠️ **UniFi variants (9, 10) require 8 GB RAM.** Running UniFi Network + Protect on 4 GB causes memory exhaustion.

---

## What you get

- **SD rescue image** — boot from SD card and install OpenWrt to NAND, eMMC, or NVMe.
- **NVMe install** — OpenWrt permanently on NVMe SSD. Includes Docker and a dedicated data partition (p3) using all remaining disk space.
- **eMMC install** — OpenWrt permanently on internal eMMC storage.
- **NAND rescue** — minimal rescue system on NAND flash, used as base for NVMe and eMMC installs.
- **Sysupgrade support** — update NVMe system directly from LuCI or command line.
- **UniFi stack** (variants 9, 10) — UniFi Protect + UniFi Network Application running in Docker on NVMe.

---

## DIP switch reference

| Boot medium  | SW3-A | SW3-B |
|--------------|-------|-------|
| SD card      | 0     | 0     |
| NAND rescue  | 0     | 1     |
| eMMC         | 1     | 0     |

> **NVMe boot** is controlled by U-Boot environment, not DIP switch. After running `install-nvme.sh`, the device boots from NVMe automatically — as long as DIP is set to **NAND** (SW3-A=0, SW3-B=1).

---

## Part A — Install from ready-made release

No setup needed. Just follow the steps below.

### Step 1 — Flash rescue SD card

1. Go to [Releases](https://github.com/woziwrt/bpi-r4-deploy/releases) and find **any release** — all releases contain the same SD rescue image `bpi-r4-rescue-sdcard.img.gz`.
2. Download `bpi-r4-rescue-sdcard.img.gz`.
3. Flash it to a microSD card using [Balena Etcher](https://etcher.balena.io/).
4. Insert the SD card into BPI-R4, set DIP **SW3-A=0, SW3-B=0** (SD boot) and power on.
5. Connect via SSH: `ssh root@192.168.1.1` (no password by default).

---

### Step 2 — Install NAND rescue system

Run from the SD card:

```sh
/root/bpi-r4-install/install-nand.sh
```

The script will ask you to select your **RAM variant (4 GB or 8 GB)**. Select the one that matches your board.

After the script finishes:

1. Power off BPI-R4.
2. Set DIP **SW3-A=0, SW3-B=1** (NAND boot) and power on.
3. Connect via SSH: `ssh root@192.168.1.1`.

---

### Step 3 — Install OpenWrt to NVMe

> ⚠️ **If you want both NVMe and eMMC:** Always run `install-emmc.sh` **before** `install-nvme.sh`. After NVMe installation, the device always boots from NVMe — eMMC installation will no longer be possible without manual intervention.

Make sure a network cable is connected, then run:

```sh
/root/bpi-r4-install/install-nvme.sh
```

The script will ask you to select your **board variant** from a menu of 10 options.

Then the script will:
- Check NVMe disk health (SMART).
- Download required images from GitHub (~150–240 MB depending on variant).
- Write OpenWrt to NVMe (p1: kernel, p2: rootfs, p3: data).
- Set up automatic NVMe boot.
- Reboot automatically.

After reboot, BPI-R4 boots from NVMe. The SD card is no longer needed.

> **Updating** — to update OpenWrt on NVMe, boot into NAND rescue (DIP SW3-A=0, SW3-B=1) and run `install-nvme.sh` again. Updates kernel and rootfs without touching data on p3.

---

### Step 3 alternative — Install to eMMC

Instead of NVMe, install to internal eMMC. From the NAND rescue system, run:

```sh
/root/bpi-r4-install/install-emmc.sh
```

After installation:
1. Power off BPI-R4.
2. Set DIP **SW3-A=1, SW3-B=0** (eMMC boot) and power on.

---

### Sysupgrade

Once running from NVMe, update OpenWrt without any scripts:

1. Find your variant's release (e.g. `release-8gb-standard`) and download `bpi-r4.itb` or `bpi-r4-poe.itb`.
2. In LuCI, go to **System → Backup / Flash Firmware**.
3. Under **Flash new firmware image**, upload the `.itb` file.
4. Uncheck **Keep settings** for a clean install, or leave it checked to keep configuration.
5. Click **Flash image** and confirm.

BPI-R4 updates kernel and rootfs and reboots automatically. Data on p3 is never touched.

---

## Part B — UniFi stack setup

### What you need

- Banana Pi R4 **8 GB RAM** (rev 1.2+ recommended — see [Hardware notes](#hardware-notes))
- NVMe SSD, minimum 500 GB (1 TB recommended for Continuous Recording)
- microSD card (temporary, 1 GB or larger)
- Ethernet cable (internet access required during installation)
- UniFi camera (G5 Flex tested)
- UniFi Access Point (U7-LR WiFi 7 tested)
- PoE switch or injector for the AP
- A [Ubiquiti account](https://account.ui.com) (optional — required only for Remote Access)

UniFi services will be available at:

| Service | Address |
|---------|---------|
| UniFi Protect | `https://192.168.1.1` |
| UniFi Network Application | `https://192.168.1.2:8443` |
| LuCI | `http://192.168.1.1:8081` |

---

### Step 4 — Install NVMe UniFi variant

Follow Part A Steps 1–2 (SD card + NAND rescue). Then instead of `install-nvme.sh`, run:

```sh
/root/bpi-r4-install/install-nvme-unifi.sh
```

Select your variant — **8GB wired UniFi** or **8GB PoE wired UniFi**.

The script downloads and installs OpenWrt with the UniFi stack prerequisites (Docker, cgroups, macvlan/dummy kernel modules). NVMe is partitioned as follows:

| Partition | Size | Purpose |
|-----------|------|---------|
| p1 | 255 MB | Boot |
| p2 | 448 MB | Root filesystem |
| p3 | 30 GB | Docker data |
| p4 | remainder | Protect storage |

After reboot, connect via SSH: `ssh root@192.168.1.1`.

---

### Step 5 — Run UniFi Protect setup

```sh
cd /mnt/nvme0n1p3
sh unifi-setup.sh
```

The script will:
- Configure Docker and hostname
- Reconfigure uhttpd (LuCI moves to port 8080)
- Set up firewall rules for Protect
- Create `enp0s2` macvlan and `enp0s1` dummy interfaces
- Download autostart scripts
- Install WAN hotplug handler
- Load the Protect Docker image (download ~2 GB or use local file)
- Create storage structure and start Protect

> ⚠️ When prompted, **disconnect the internet cable** before pressing Enter. This is required for first-time Protect setup.

---

### Step 6 — First-time Protect configuration

1. Open `https://192.168.1.1` in your browser.
2. Accept the SSL warning (self-signed certificate — expected).
3. On the **No Internet Detected** screen, choose **Other Configuration Options → Local Network → Set Up Console Offline**.
4. Enter a name for your console (e.g. `BPI-R4-UniFi`) and click **Next**.
5. Set a password and click **Finish**.
6. Wait for **Setup Complete!** and click **Go to Dashboard**.

**Immediately after first login — disable auto-updates:**

Go to **Settings (gear icon) → Control Plane → Updates** and disable all Auto-Update options.

> ⚠️ Leaving auto-update enabled risks breaking the installation with an incompatible version.

---

### Step 7 — Run UniFi Network Application setup

Reconnect the internet cable, then:

```sh
cd /mnt/nvme0n1p3
sh unifi-network-setup.sh
```

The script will:
- Move LuCI to port 8081 (freeing 8080 for Network Application)
- Set up `enp0s3` macvlan interface at `192.168.1.2`
- Configure nftables firewall rules for Docker bridge networks
- Create 2 GB swap file on p3
- Pull and start Network Application + MongoDB containers

---

### Step 8 — First-time Network Application configuration

1. Open `https://192.168.1.2:8443` in your browser.
2. Accept the SSL warning.
3. Complete the setup wizard.
4. Go to **Settings → System** and disable auto-updates.

---

### Adding a camera

1. Connect the camera via ethernet to a LAN port and power it on.
2. Perform a hardware reset (hold reset button until LED changes).
3. In the Protect dashboard → **Devices** — the camera should appear and can be adopted.
4. Camera status dot turns green — camera is online.

---

### Adopting an Access Point

After factory reset, the AP will not auto-discover the Network Application. Use SSH set-inform:

```sh
ssh ubnt@<AP_IP> "/usr/bin/syswrapper.sh set-inform http://192.168.1.2:8080/inform"
```

`<AP_IP>` is visible in LuCI: `http://192.168.1.1:8081` → Network → DHCP Leases

Default credentials after factory reset: `ubnt` / `ubnt`

Once adopted, the AP remembers the controller address and reconnects automatically after reboots.

---

## Part C — Fork and customize

Fork this repository to build your own customized release.

### Step 1 — Fork the repository

Fork this repository on GitHub. **Do not rename the fork** — it must stay named `bpi-r4-deploy`, otherwise the install scripts will not find your release.

### Step 2 — Enable workflows and set permissions

1. Go to the **Actions** tab in your fork and enable workflows.
2. Open **Settings → Actions → General** and set:
   - **Actions permissions**: Allow all actions and reusable workflows.
   - **Workflow permissions**: **Read and write permissions** — required to create releases.

> ⚠️ Without **Read and write permissions** the workflow will fail when trying to create a release.

### Step 3 — Customize packages

1. Open `my_defconfig-universal` or `my_defconfig-wired-universal` depending on your variant.
2. Edit lines like:
   ```
   CONFIG_PACKAGE_iperf3=y
   # CONFIG_PACKAGE_htop is not set
   ```
   - `=y` → package enabled
   - `is not set` → package disabled
3. **Only change lines starting with `CONFIG_PACKAGE_`.** Do not touch kernel, target, or MTK SDK options.

### Step 4 — Trigger a build

1. Go to the **Actions** tab in your fork.
2. Select **Build BPI-R4 Deploy**.
3. Click **Run workflow**:
   - **standard** — builds all WiFi variants (4GB + 8GB, standard + PoE) → 4 releases.
   - **wired** — builds all wired variants (4GB + 8GB, standard + PoE + UniFi) → 6 releases.
4. After the workflow finishes (~2 hours), releases will be created in your fork.

### Step 5 — Install from your fork

When running `install-nvme.sh` or `install-emmc.sh`, select option **[2] My fork** and enter your GitHub username.

---

## Architecture

| Component | Role |
|-----------|------|
| BPI-R4 | Routing, firewall, Docker runtime, NVMe storage |
| UniFi Protect | Camera management ([dciancu](https://github.com/dciancu/unifi-protect-unvr-docker-arm64) Docker image) |
| UniFi Network Application | WiFi management (linuxserver Docker image) |
| UniFi AP | Professional WiFi (U7-LR WiFi 7 tested) |

This deliberately avoids the known signal/noise issues of the BPI-R4's onboard BE14 WiFi module while delivering enterprise-grade WiFi through a proper UniFi AP.

---

## NVMe partition layout

| Partition | Size | Purpose |
|-----------|------|---------|
| p1 | 255 MB | Boot |
| p2 | 448 MB | Root filesystem |
| p3 | 30 GB (dev) / 15 GB (prod) | Docker data |
| p4 | remainder | Protect storage (Continuous Recording requires 100 GB+) |

---

## Hardware notes

### BPI-R4 rev 1.0 known issues

| Issue | Details |
|-------|---------|
| NVMe + SFP conflict | Some NVMe disks pull down the I2C bus, disabling SFP ports and other I2C devices |
| Affected disks | Chinese OEM NVMe drives (e.g. generic 128 GB) |
| Not affected | Samsung EVO series — SFP ports remain functional |
| Fixed in | Rev 1.2+ — Sinovoip resolved the I2C/NVMe conflict in hardware |

For new builds, **BPI-R4 8 GB RAM rev 1.2+** is recommended — NVMe and SFP ports work simultaneously and 8 GB RAM provides headroom for Docker workloads.

---

## Known behaviors

### Boot time

After a cold boot or reboot, allow approximately **4–5 minutes** for the router to become fully operational. During this time, brief connectivity interruptions are normal — Docker containers, UniFi Protect, and UniFi Network Application initialize sequentially and each triggers a firewall reload. This is expected behavior.

Approximate timeline after boot:
- ~1 min — router reachable via SSH/LuCI
- ~3 min — UniFi Protect available
- ~8–10 min — UniFi Network Application fully initialized

### WAN reconnect

When WAN goes down and comes back up, OpenWrt performs a `fw4 reload` which clears custom nftables rules required by the Docker bridge network. The installed hotplug handler (`99-docker-nft`) restores these rules automatically — no reboot needed.

> UniFi Protect is not affected — it runs with `network_mode: host` and does not depend on bridge nftables rules.

### GitHub runner disk space

This workflow runs on GitHub-hosted runners where free disk space is not guaranteed. If a build fails with a disk-related error, re-run the workflow — runners with sufficient space are usually available shortly.

---

## Repository contents

| File / Directory | Description |
|------------------|-------------|
| `builder-universal.sh` | Build script for all WiFi variants |
| `builder-wired-universal.sh` | Build script for all wired variants (includes Docker/UniFi prerequisites) |
| `my_defconfig-universal` | Package config for WiFi builds |
| `my_defconfig-wired-universal` | Package config for wired builds |
| `my_files/` | Patches, custom files, install scripts |
| `rescue/bpi-r4-rescue-sdcard.img.gz` | Static rescue SD card image (same for all variants) |
| `unifi/` | UniFi stack scripts (distributed in UniFi releases) |
| `.github/workflows/build-bpi-r4-deploy.yml` | Build workflow |

### Telit/Cinterion modem LuCI extensions

All builds include LuCI extensions for Telit/Cinterion LTE/5G modules (FN980/FN990 family). These are harmless if you don't have these modules — two extra entries appear in the LuCI menu but do nothing. To remove them:

```sh
apk del luci-app-modemdata luci-app-sms-tool-js luci-app-lite-watchdog
```

---

<img width="1264" height="1080" alt="UniFi Protect dashboard" src="https://github.com/user-attachments/assets/1483d00f-839a-4ced-b899-6d688e0483a7" />

<img width="1264" height="1080" alt="UniFi Network Application" src="https://github.com/user-attachments/assets/f912c22e-a31c-42e6-8fc7-34e1632a8bc7" />

<img width="1264" height="1080" alt="LuCI dashboard" src="https://github.com/user-attachments/assets/ae709b45-ad2a-44ff-ab7b-73b9d5f1d6d9" />

<img width="1264" height="1080" alt="UniFi camera view" src="https://github.com/user-attachments/assets/b6ce49af-bd91-4a67-87b2-c77ee121f051" />

<img width="1264" height="1080" alt="UniFi device list" src="https://github.com/user-attachments/assets/ae709b45-ad2a-44ff-ab7b-73b9d5f1d6d9" />

<img width="660" height="1434" alt="BPI-R4 hardware" src="https://github.com/user-attachments/assets/aac7b973-ccdf-469f-b027-d8755032469c" />

<img width="660" height="1434" alt="BPI-R4 setup" src="https://github.com/user-attachments/assets/a703787d-9e16-4195-b495-65b1b4334ca6" />

<img width="660" height="1434" alt="BPI-R4 with camera" src="https://github.com/user-attachments/assets/a703787d-9e16-4195-b495-65b1b4334ca6" />

<img width="660" height="1434" alt="BPI-R4 UniFi stack" src="https://github.com/user-attachments/assets/be266889-b238-4aba-b3b7-53dba31d7e86" />

---

*This project is not affiliated with Ubiquiti Inc. in any way.*

*🍌 TEAM WOZIWRT+CLAUDE*
