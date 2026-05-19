# OpenWrt for Banana Pi BPI-R4 — 4GB PoE WiFi

> Bu repo, **Banana Pi BPI-R4 (4GB RAM, PoE, WiFi)** için sadece tek varyant içerir.

## Özellikler

- **RAM:** 4GB
- **PoE:** 2.5GE PoE port desteği
- **WiFi:** WiFi 7 (BE14 modülü) desteği — Ivan Mironov'un tx_power yaması dahil
- **Kurulum:** NVMe, eMMC, NAND ve SD kart desteği

## Hızlı Başlangıç

### Hazır Görüntüden Kurulum

1. [Releases](../../../releases) bölümünden **release-4gb-poe-wifi** dosyalarını indir.
2. SD rescue imajını (`bpi-r4-rescue-sdcard.img.gz`) microSD karta yaz.
3. BPI-R4'e tak, DIP **SW3-A=0, SW3-B=0** ayarla, güç ver.
4. SSH ile bağlan: `ssh root@192.168.1.1`
5. NAND rescue kurulumu: `/root/bpi-r4-install/install-nand.sh`
6. Yeniden başlat, DIP **SW3-A=0, SW3-B=1** ayarla.
7. NVMe kurulumu: `/root/bpi-r4-install/install-nvme.sh`

### Build Etme

```bash
./builder.sh
```

### Kurulum Dosyaları

| Dosya | Açıklama |
|-------|----------|
| `bpi-r4.itb` | Sysupgrade imajı |
| `bpi-r4-poe.itb` | PoE sysupgrade imajı |
| `*.nvme-img.bin` | NVMe disk imajı |
| `*.sdcard.img.gz` | SD kart imajı |
| `*.emmc-img.bin` | eMMC imajı |
| `*.snand-img.bin` | SNAND imajı |

## Sistem Gereksinimleri

- Banana Pi BPI-R4 rev 1.0 veya 1.1 (4GB RAM)
- NVMe SSD veya eMMC
- microSD kart (geçici)
- Ethernet kablosu

## Yapı

```
.
├── builder.sh              # Ana OpenWrt build betiği
├── bpi-r4-rescue-{nand,sd}.sh  # Rescue imaj build betikleri
├── configs/
│   └── my_defconfig-4gb-poe-wifi  # OpenWrt yapılandırması
├── my_files/                 # Yamalar ve özelleştirmeler
├── rescue/                     # Rescue SD kart imajı
└── README.md
```

## 4GB PoE WiFi Yapılandırması

`configs/my_defconfig-4gb-poe-wifi` içinde:

- `CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_bananapi_bpi-r4-poe=y`
- `CONFIG_DRIVER_11BE_SUPPORT=y` — WiFi 7 desteği
- `CONFIG_PACKAGE_*` modem, LuCI GUI, kmod vb.

## PoE Notları

PoE portu, BPI-R4 üzerindeki 2.5GE Ethernet portudur. Destek pasif PoE (IEEE 802.3af/at/bt). Doğrudan giriş gücü gerekmez. En uygun PoE switch/injektör ile birlikte çalışır.

## WiFi Notları

- BE14 modülü üzerinde çalışır
- IEEE 802.11be (WiFi 7) destekli
