# OpenWrt + UniFi Stack for Banana Pi BPI-R4 & BPI-R4 Pro 8X

Run **OpenWrt** on Banana Pi BPI-R4 and **BPI-R4 Pro 8X** (MT7988A, Wi-Fi 7) with an optional **UniFi Protect + UniFi Network Application** stack — a cost-effective alternative to the Ubiquiti UNVR + Cloud Gateway combo.

Complete install system that runs entirely on GitHub — no Linux machine needed.

> **Tested hardware:** Banana Pi R4 rev 1.0 (4GB) · Banana Pi R4 rev 1.1 (8GB) · Banana Pi R4 Pro 8X · UniFi G5 Flex camera · UniFi U7-LR WiFi 7 AP

---

## Contents

- [Board variants](#board-variants)
- [DIP switch reference](#dip-switch-reference)
- [Part A — BPI-R4: Install](#part-a--bpi-r4-install)
  - [Step 1 — Flash rescue SD card](#step-1--flash-rescue-sd-card)
  - [Step 2 — Install NAND system](#step-2--install-nand-system)
  - [Step 3 — Install OpenWrt to NVMe](#step-3--install-openwrt-to-nvme)
  - [Step 3 alternative — Install to eMMC](#step-3-alternative--install-to-emmc)
- [Part B — BPI-R4: UniFi stack](#part-b--bpi-r4-unifi-stack)
- [Part C — BPI-R4 Pro 8X: Install](#part-c--bpi-r4-pro-8x-install)
  - [Step 1 — Flash SD card](#step-1--flash-sd-card-1)
  - [Step 2 — Install NAND system](#step-2--install-nand-system-1)
  - [Step 3 — Optional: Install to eMMC](#step-3--optional-install-to-emmc)
  - [Step 4 — Install OpenWrt to NVMe](#step-4--install-openwrt-to-nvme)
  - [Switching between NAND and NVMe](#switching-between-nand-and-nvme)
- [Part D — BPI-R4 Pro 8X: UniFi stack](#part-d--bpi-r4-pro-8x-unifi-stack)
- [Part E — Fork and customize](#part-e--fork-and-customize)
- [Architecture](#architecture)
- [NVMe partition layout](#nvme-partition-layout)
- [Hardware notes](#hardware-notes)
- [Known behaviors](#known-behaviors)

---

## Board variants

### BPI-R4

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

### BPI-R4 Pro 8X

| Variant | RAM | WiFi | Notes |
|---------|-----|------|-------|
| Pro 8X WiFi | 8 GB | ✅ | BPI-R4 Pro 8X with WiFi 7 |
| Pro 8X wired | 8 GB | ❌ | BPI-R4 Pro 8X, no WiFi |

---

## DIP switch reference

| Boot medium | A | B |
|-------------|---|---|
| SD card     | 1 | 1 |
| NAND        | 0 | 1 |
| eMMC        | 1 | 0 |

> **NVMe boot** is controlled by U-Boot environment, not DIP switch. After running `install-nvme.sh`, the device boots from NVMe automatically — DIP stays at **NAND** (A=0, B=1) and is never changed again.

> NAND and eMMC are fully functional permanent options. NVMe is recommended for larger storage needs — required for the UniFi stack.

---

## Part A — BPI-R4: Install

### Step 1 — Flash rescue SD card

1. Go to [Releases](https://github.com/woziwrt/bpi-r4-deploy/releases) and find **any release** — all releases contain the same SD rescue image `bpi-r4-rescue-sdcard.img.gz`.
2. Download `bpi-r4-rescue-sdcard.img.gz`.
3. Flash it to a microSD card using [Balena Etcher](https://etcher.balena.io/).
4. Insert the SD card, set DIP **A=1, B=1** (SD boot) and power on.
5. Connect via SSH: `ssh root@192.168.1.1` (no password).

---

### Step 2 — Install NAND system

Run from the SD card:

```
/root/install-dir/install-nand.sh
```

Select your **RAM variant (4 GB or 8 GB)**.

After the script finishes:

1. Power off.
2. Set DIP **A=0, B=1** (NAND boot) and power on.
3. Connect via SSH: `ssh root@192.168.1.1`.

---

### Step 3 — Install OpenWrt to NVMe

> ⚠️ **If you want both NVMe and eMMC:** Run `install-emmc.sh` **before** `install-nvme.sh`. After NVMe installation the device always boots from NVMe.

Make sure a WAN cable is connected, then run:

```
/root/install-dir/install-nvme.sh
```

Select your **board variant** from the menu. The script checks NVMe health, downloads images (~150–240 MB), writes OpenWrt to NVMe and reboots automatically.

> **Updating** — to update OpenWrt on NVMe, boot into NAND (DIP A=0, B=1) and run `install-nvme.sh` again. Data on p3 is never touched.

---

### Step 3 alternative — Install to eMMC

```
/root/install-dir/install-emmc.sh
```

After installation set DIP **A=1, B=0** (eMMC boot) and power on.

---

## Part B — BPI-R4: UniFi stack

### What you need

- BPI-R4 **8 GB RAM** (rev 1.2+ recommended)
- NVMe SSD, minimum 500 GB (1 TB recommended for Continuous Recording)
- UniFi camera (G5 Flex tested) · UniFi AP (U7-LR WiFi 7 tested)
- A [Ubiquiti account](https://account.ui.com) (optional — required only for Remote Access)

| Service | Address |
|---------|---------|
| UniFi Protect | `https://192.168.1.1` |
| UniFi Network Application | `https://192.168.1.2:8443` |
| LuCI | `http://192.168.1.1:8081` |

---

### Step 4 — Install NVMe UniFi variant

Follow Steps 1–2 above, then run:

```
/root/install-dir/install-nvme.sh
```

Select variant **9** (8GB wired UniFi) or **10** (8GB PoE wired UniFi).

---

### Step 5 — Run UniFi Protect setup

> ⚠️ **Run from SSH terminal only — not from LuCI terminal (ttyd).** The script modifies the firewall and a ttyd session will be interrupted.

```
cd /mnt/nvme0n1p3
sh unifi-setup.sh
```

> ⚠️ When prompted, **disconnect the WAN cable** before pressing Enter.

---

### Step 6 — First-time Protect configuration

1. Open `https://192.168.1.1`.
2. Accept the SSL warning (self-signed certificate).
3. **Other Configuration Options → Local Network → Set Up Console Offline**.
4. Enter a console name, set a password, click **Finish**.

**Immediately disable auto-updates: Settings → Control Plane → Updates.**

---

### Step 7 — Run UniFi Network Application setup

Reconnect the WAN cable, then:

```
cd /mnt/nvme0n1p3
sh unifi-network-setup.sh
```

---

### Step 8 — First-time Network Application configuration

1. Open `https://192.168.1.2:8443`.
2. Complete the setup wizard.
3. **Settings → System** — disable auto-updates.

---

### Adding a camera

1. Connect the camera to a LAN port and power it on.
2. Hardware reset (hold reset button until LED changes).
3. Protect dashboard → **Devices** — camera appears for adoption.

---

### Adopting an Access Point

1. Connect the AP to a LAN port and power it on.
2. Hardware reset (hold reset button until LED changes).
3. Network Application dashboard → **Devices** — AP appears for adoption.

---

## Part C — BPI-R4 Pro 8X: Install

BPI-R4 Pro 8X uses a different SoC configuration, NAND layout, and device trees than the standard BPI-R4. **Pro 8X images are not compatible with standard BPI-R4 and vice versa.**

### What you need

- BPI-R4 Pro 8X board
- **NVMe SSD in slot CN14 (M-key), minimum 512 GB** — tested with Patriot P300 512 GB. CN15 and CN18 are B-key slots for LTE modems, not NVMe.
- microSD card (temporary, for install only)
- For WAN and LAN connectivity: SFP or SFP copper modules are recommended

---

### Step 1 — Flash SD card

1. Go to [Releases](https://github.com/woziwrt/bpi-r4-deploy/releases) and download the SD card image from **release-pro-8x-wired** or **release-pro-8x-standard**:
   `openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-sdcard.img.gz`
2. Flash to a microSD card using [Balena Etcher](https://etcher.balena.io/).
3. Insert SD card, set DIP **A=1, B=1** (SD boot) and power on.
4. Connect via SSH: `ssh root@192.168.1.1` (no password).

---

### Step 2 — Install NAND system

Connect the WAN cable, then run:

```
/root/install-dir/install-nand.sh
```

After the script finishes:

1. Power off.
2. Set DIP **A=0, B=1** (NAND boot) and power on.
3. Connect via SSH: `ssh root@192.168.1.1`.

---

### Step 3 — Optional: Install to eMMC

> ⚠️ **Run this before `install-nvme.sh`.** After NVMe installation the device always boots from NVMe.

```
/root/install-dir/install-emmc.sh
```

Select **1** (Pro 8X WiFi) or **2** (Pro 8X wired).

After installation set DIP **A=1, B=0** (eMMC boot) to use eMMC, or keep DIP at A=0, B=1 and continue with NVMe install.

---

### Step 4 — Install OpenWrt to NVMe

From the NAND system, connect the WAN cable and run:

```
/root/install-dir/install-nvme.sh
```

Select **1** (Pro 8X WiFi) or **2** (Pro 8X wired).

The script checks NVMe health, downloads images (~150 MB), writes OpenWrt to NVMe and reboots automatically.

**After reboot the router boots from NVMe.** DIP stays at A=0, B=1 permanently — this is correct.

---

### Switching between NAND and NVMe

```
boot-nand    # switch to NAND on next reboot
boot-nvme    # switch back to NVMe on next reboot
```

---

## Part D — BPI-R4 Pro 8X: UniFi stack

Pro 8X wired is ideal for running the UniFi stack — 8 GB RAM, NVMe storage, and no onboard WiFi interference.

### What you need

- BPI-R4 Pro 8X (wired variant recommended)
- NVMe SSD in slot CN14, **minimum 512 GB** (1 TB recommended for Continuous Recording)
- UniFi camera (G5 Flex tested) · UniFi AP (U7-LR WiFi 7 tested)
- A [Ubiquiti account](https://account.ui.com) (optional — required only for Remote Access)

| Service | Address |
|---------|---------|
| UniFi Protect | `https://192.168.1.1` |
| UniFi Network Application | `https://192.168.1.1:8443` |
| LuCI | `http://192.168.1.1:8080` |

---

### Step 4 — Install NVMe UniFi variant

Follow Part C Steps 1–2, then run:

```
/root/install-dir/install-nvme-unifi.sh
```

Select **1** (Pro 8X WiFi) or **2** (Pro 8X wired).

---

### Step 5 — Run UniFi Protect setup

> ⚠️ **Run from SSH terminal only — not from LuCI terminal (ttyd).** The script modifies the firewall and a ttyd session will be interrupted.

```
sh /mnt/nvme0n1p3/unifi-setup.sh
```

When asked to download or use a local file — select **[1] Download**. The script downloads the Docker image (~660 MB) and loads it automatically.

> ⚠️ When prompted, **disconnect the WAN cable** before pressing Enter.

---

### Step 6 — First-time Protect configuration

1. Open `https://192.168.1.1`.
2. Accept the SSL warning (self-signed certificate).
3. **Other Configuration Options → Local Network → Set Up Console Offline**.
4. Enter a console name, set a password, click **Finish**.

**Immediately disable auto-updates: Settings → General → Auto Update.**

---

### Step 7 — Run UniFi Network Application setup

Reconnect the WAN cable, then:

```
sh /mnt/nvme0n1p3/unifi-network-setup.sh
```

---

### Step 8 — First-time Network Application configuration

1. Open `https://192.168.1.1:8443`.
2. Complete the setup wizard.
3. **Settings → System** — disable auto-updates.

---

### Adding a camera and Access Point

Same procedure as Part B — see [Adding a camera](#adding-a-camera) and [Adopting an Access Point](#adopting-an-access-point).

---

## Part E — Fork and customize

Fork this repository to build your own customized release.

1. Fork on GitHub. **Do not rename the fork** — it must stay named `bpi-r4-deploy`.
2. Go to **Settings → Actions → General** → set **Workflow permissions** to **Read and write**.
3. Go to **Actions → Build BPI-R4 Pro 8X → Run workflow**, select **Pro-8X-wifi** or **Pro-8X-wired**.
4. After ~2 hours, releases appear in your fork.

To install from your fork, edit `GH_USER` at the top of the install scripts.

---

## Architecture

| Component | Role |
|-----------|------|
| BPI-R4 / Pro 8X | Routing, firewall, Docker runtime, NVMe storage |
| UniFi Protect | Camera management ([dciancu](https://github.com/dciancu/unifi-protect-unvr-docker-arm64) Docker image) |
| UniFi Network Application | WiFi management (linuxserver Docker image) |
| UniFi AP | Professional WiFi (U7-LR WiFi 7 tested) |

---

## NVMe partition layout

| Partition | Size | Purpose |
|-----------|------|---------|
| p1 | 256 MB | Boot (kernel) |
| p2 | 512 MB | Root filesystem |
| p3 | remainder | Data / Docker / UniFi storage |

---

## Hardware notes

### BPI-R4 rev 1.0 known issues

| Issue | Details |
|-------|---------|
| NVMe + SFP conflict | Some NVMe disks pull down the I2C bus, disabling SFP ports |
| Affected disks | Chinese OEM NVMe drives (e.g. generic 128 GB) |
| Not affected | Samsung EVO series |
| Fixed in | Rev 1.2+ |

For new builds, **BPI-R4 8 GB RAM rev 1.2+** is recommended.

---

## Known behaviors

### Boot time

After a cold boot or reboot, allow approximately **4–5 minutes** for the router to become fully operational.

Approximate timeline:
- ~1 min — router reachable via SSH/LuCI
- ~3 min — UniFi Protect available
- ~8–10 min — UniFi Network Application fully initialized

### WAN reconnect

When WAN goes down and comes back up, the installed hotplug handler (`99-docker-nft`) restores Docker nftables rules automatically — no reboot needed.

### NAND first boot — UBI messages

On the very first boot into the NAND system, U-Boot may print messages like:

```
UBI: Bad EC magic in block XXXX
```

This is normal — U-Boot is initializing the NAND flash. The messages disappear on subsequent boots.

### GitHub runner disk space

If a build fails with a disk-related error, re-run the workflow — runners with sufficient space are usually available shortly.

---

<img width="1264" height="1080" alt="UniFi Protect dashboard" src="https://github.com/user-attachments/assets/1483d00f-839a-4ced-b899-6d688e0483a7" />

<img width="1264" height="1080" alt="UniFi Network Application" src="https://github.com/user-attachments/assets/f912c22e-a31c-42e6-8fc7-34e1632a8bc7" />

<img width="1264" height="1080" alt="LuCI dashboard" src="https://github.com/user-attachments/assets/ae709b45-ad2a-44ff-ab7b-73b9d5f1d6d9" />

<img width="1264" height="1080" alt="UniFi camera view" src="https://github.com/user-attachments/assets/b6ce49af-bd91-4a67-87b2-c77ee121f051" />

---

*This project is not affiliated with Ubiquiti Inc. in any way.*

*🍌 TEAM WOZIWRT+CLAUDE*
