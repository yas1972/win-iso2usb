# win-iso2usb

A lightweight, high-performance Bash script for Linux to create bootable Windows 10/11 USB installer drives from official ISO images. It implements a **Rufus-like dual-partition mechanism** to achieve maximum UEFI compatibility while bypassing strict FAT32 file size limits.

## 🚀 Key Features

* **Rufus-like Layout:** Automatically splits the USB stick into a small bootable FAT32 partition (64MB) for UEFI initialization and a large NTFS partition for the actual installation assets.
* **No `install.wim` Splitting:** Preserves the integrity of monolithic official Microsoft Windows images. Heavy `.wim` or `.esd` files are stored intact on the NTFS partition.
* **On-the-Fly Streaming:** Mounts the ISO directly and streams data straight to the USB. No heavy temporary duplication on your local SSD/HDD.
* **Smart Size Validation:** Proactively checks the low-level capacity of the connected USB drive against the ISO size before altering any bytes.
* **Safety First:** Prevents execution on wrong inputs (demands a whole drive path like `/dev/sdh`, not a partition) and automatically blocks any attempts to write to critical active system mount points (`/`, `/home`, etc.).

## 🛠️ Prerequisites

The script requires standard Linux partitioning and file system tools. If any are missing, it will gently inform you. 

On **Debian / Ubuntu / Linux Mint**, run the following command to make sure you are ready:
```bash
sudo apt install fdisk dosfstools ntfs-3g rsync parted
```

## 📦 Installation

To make the script globally accessible as a system-wide command, deploy it to `/usr/local/sbin/`:

1. Copy the script to the destination directory:
   ```bash
   sudo nano /usr/local/sbin/win-iso2usb
   ```
2. Make it executable:
   ```bash
   sudo chmod +x /usr/local/sbin/win-iso2usb
   ```
3. Set proper secure ownership:
   ```bash
   sudo chown root:root /usr/local/sbin/win-iso2usb
   ```

## 📖 Usage

Run the tool by providing the path to your official Windows ISO file and the **entire letter node** of your USB drive (do not specify partition numbers):

```bash
sudo win-iso2usb <path_to_windows.iso> <entire_usb_device>
```

### Example:
```bash
sudo win-iso2usb Windows11_English_x64v1.iso /dev/sdh
```

## ⚠️ Important Hardware Troubleshooting
If you are installing Windows on modern platforms (e.g., AMD Ryzen processors with integrated graphics or newer Intel architectures) and the Windows installer says **"A required media driver is missing"** or shows a blank drive selection window:
1. Ensure your M.2 NVMe SSD is plugged into the **primary M.2 slot** directly connected to the CPU.
2. Enter your motherboard BIOS and change **SATA Mode** from *RAID* to **AHCI**.
3. Disable **CSM (Compatibility Support Module)** in your BIOS settings to enforce pure UEFI boot initialization.

## 📄 License
This project is open-source and free to use.

---
**Created by:** Yuri A. Soshnikov ([yas1972@yandex.ru](mailto:yas1972@yandex.ru))  
**Refined with:** AI Collaborator


