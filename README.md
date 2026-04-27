# ⚠️ UNDER DEVELOPMENT — DO NOT USE

This branch is work in progress for BPI-R4 8GB DDR4 RAM support.
Not tested, not ready for production use.

For stable release see: [main branch](https://github.com/woziwrt/bpi-r4-deploy)


# OpenWrt for Banana Pi BPI-R4 (kernel 6.12)

OpenWrt 25.12 for Banana Pi BPI-R4 (MT7988, Wi-Fi 7) with a complete install system that runs entirely on GitHub — no Linux machine needed.

---

## Board variants

This project supports all BPI-R4 variants. Select yours during installation:

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
- **NVMe install** — install OpenWrt permanently to an NVMe SSD. Includes Docker and a dedicated data partition (p3) that uses all remaining disk space.
- **eMMC install** — install OpenWrt permanently to the internal eMMC storage.
- **NAND rescue** — a minimal rescue system stored on NAND flash, used as a base for NVMe and eMMC installs.
- **Sysupgrade support** — update your NVMe system directly from LuCI or the command line.

---

## DIP switch reference

| Boot medium  | SW3-A | SW3-B |
|--------------|-------|-------|
| SD card      | 0     | 0     |
| NAND rescue  | 0     | 1     |
| eMMC         | 1     | 0     |

> **NVMe boot** is controlled by U-Boot environment, not by DIP switch. After running `install-nvme.sh`, the device boots from NVMe automatically — as long as DIP is set to **NAND** (SW3-A=0, SW3-B=1).

---

## Part A — Install from the ready-made release

No setup needed. Just follow the steps below.

### Step 1 — Flash the rescue SD card

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

Wait for the script to finish. Then:

1. Power off BPI-R4.
2. Set DIP **SW3-A=0, SW3-B=1** (NAND boot) and power on.
3. Connect via SSH: `ssh root@192.168.1.1`.

---

### Step 3 — Install OpenWrt to NVMe (recommended)

> ⚠️ **If you want both NVMe and eMMC:** Always run `install-emmc.sh` **before** `install-nvme.sh`. After NVMe installation, the device always boots from NVMe — eMMC installation will no longer be possible without manual intervention.

Make sure a network cable is connected, then run:

```sh
/root/bpi-r4-install/install-nvme.sh
```

The script will ask you to select your **board variant** from a menu of 10 options. Select the one that matches your board.

Then the script will:
- Check your NVMe disk health (SMART).
- Download the required images from GitHub automatically (~150–240 MB depending on variant).
- Write OpenWrt to your NVMe SSD (p1: kernel, p2: rootfs, p3: data).
- Set up automatic NVMe boot.
- Reboot automatically.

After reboot, BPI-R4 boots from NVMe. The SD card is no longer needed.

> **Updating** — to update OpenWrt on NVMe, boot into NAND rescue (DIP SW3-A=0, SW3-B=1) and run `install-nvme.sh` again. It updates kernel and rootfs without touching your data on p3.

---

### Step 3 (alternative) — Install OpenWrt to eMMC

Instead of NVMe, you can install to the internal eMMC. From the NAND rescue system, run:

```sh
/root/bpi-r4-install/install-emmc.sh
```

The script will ask you to select your **board variant** from the same menu of 10 options.

After installation:
1. Power off BPI-R4.
2. Set DIP **SW3-A=1, SW3-B=0** (eMMC boot) and power on.

---

### Sysupgrade (updating NVMe system from LuCI)

Once running from NVMe, you can update OpenWrt without any scripts:

1. Find your variant's release (e.g. `release-8gb-standard`) and download `bpi-r4.itb` or `bpi-r4-poe.itb`.
2. In LuCI, go to **System → Backup / Flash Firmware**.
3. Under **Flash new firmware image**, upload the `.itb` file.
4. Uncheck **Keep settings** for a clean install, or leave it checked to keep your configuration.
5. Click **Flash image** and confirm.

BPI-R4 will update kernel and rootfs and reboot automatically. Your data on p3 is never touched.

---

## Part B — Fork and customize (advanced users)

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

1. In your fork, open `my_defconfig.universal` or `my_defconfig.wired-universal` depending on your variant.
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
3. Click **Run workflow**. You will see two options:
   - **Build variant** — select what you want to build:
     - **standard** — builds all WiFi variants (4GB + 8GB, standard + PoE) → 4 releases.
     - **wired** — builds all wired variants (4GB + 8GB, standard + PoE + UniFi) → 6 releases.
   - **Commit hash** — leave empty to build the latest version.
4. Click **Run workflow**.
5. After the workflow finishes (approx. 2 hours), releases will be created in your fork with the appropriate tags.

### Step 5 — Install from your fork

When running `install-nvme.sh` or `install-emmc.sh`, select option **[2] My fork** and enter your GitHub username:

```
  [1] Default (woziwrt/bpi-r4-deploy)
  [2] My fork (same repo name, different username)

  Select [1/2]: 2
        Enter your GitHub username: johndoe
```

> ⚠️ Make sure you have triggered a build in your fork and the release exists before running the install script.

---

## Repository contents

| File / Directory | Description |
|------------------|-------------|
| `builder-universal.sh` | Build script for all WiFi variants (4GB + 8GB, standard + PoE). |
| `builder-wired-universal.sh` | Build script for all wired variants (4GB + 8GB, standard + PoE + UniFi). |
| `my_defconfig.universal` | Package config for WiFi builds. |
| `my_defconfig.wired-universal` | Package config for wired builds (includes Docker/UniFi prerequisites). |
| `my_files/` | Patches, custom files, install scripts. |
| `rescue/bpi-r4-rescue-sdcard.img.gz` | Static rescue SD card image (single image for all variants). |
| `.github/workflows/build-bpi-r4-deploy.yml` | Workflow — select standard or wired at run time. |

---

## Notes

- This build is for Banana Pi BPI-R4 only (MT7988, 2x SFP+).
- OpenWrt and MTK SDK commits are pinned in the build scripts. Updating them requires manual editing.
- Docker is included in all builds but does not start automatically. To start Docker: `/etc/init.d/dockerd start`
- The wired builds include all kernel prerequisites for Docker and UniFi stack (cgroup memory accounting).

### Notes about GitHub runners

This workflow runs on GitHub-hosted runners where free disk space is not guaranteed. If a build fails with a disk-related error, re-run the workflow — runners with sufficient space are usually available within a short time.

External mirrors used during the build can also be temporarily slow or unavailable. Re-running the workflow later usually resolves this.
