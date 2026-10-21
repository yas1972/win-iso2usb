# win-iso2usb

A lightweight Bash script to create bootable Windows 10/11 USB drives directly from Linux. It is optimized for modern UEFI systems and AMD Ryzen / Intel processors with specific PCIe architectures.

## 🚀 Features
* **Direct Streaming (Fast & Safe):** No more wasting time copying gigabytes of data to temporary directories like `/tmp`. Files are read directly from the mounted ISO image and streamed straight to the USB drive, saving your SSD's lifespan.
* **Rufus Method under Linux:** Automatically creates a dual-partition layout on the USB flash drive (a small FAT32 partition for the UEFI bootloader and a large NTFS partition for the actual OS data).
* **No WIM Splitting:** The heavy `install.wim` file is copied monolithically. This guarantees the original Microsoft installer runs exactly as intended and fixes the classic "No drives found" or "Missing media driver" errors during Windows setup.

## 🛠 Dependencies
The script relies on standard system utilities for partitioning and formatting. Most Linux distributions have them pre-installed:
`sfdisk`, `mkfs.fat`, `mkfs.ntfs`, `ntfs-3g`, `rsync`, `parted`.

On **Debian / Ubuntu**, you can install all missing tools with a single command:
```bash
sudo apt install fdisk dosfstools ntfs-3g rsync parted
```

## 📦 Installation
For quick access from anywhere in your system, it is recommended to place the script in your local system binaries directory:
```bash
sudo cp win-iso2usb /usr/local/sbin/win-iso2usb
sudo chmod +x /usr/local/sbin/win-iso2usb
sudo chown root:root /usr/local/sbin/win-iso2usb
```

## 💻 Usage
Run the script by passing the path to your official Windows ISO image and the **target drive device as a whole** (e.g., `/dev/sdh`, NOT an individual partition like `/dev/sdh1`):

```bash
sudo win-iso2usb /path/to/Windows.iso /dev/sdh
```

---
*Created by: Yuri A. Soshnikov (yas1972@yandex.ru)*  
*Modified & Fixed with AI Collaborator*

# win-iso2usb

Легковесный Bash-скрипт для создания загрузочных флешек Windows 10/11 из-под Linux. Идеально подходит для современных систем UEFI и процессоров AMD Ryzen/Intel со специфической архитектурой PCIe.

## 🚀 Особенности
* **Прямой стриминг (Fast & Safe):** Больше никаких временных файлов в `/tmp`. Данные копируются «на лету» напрямую из ISO на USB, что экономит ресурс вашего SSD.
* **Метод Rufus под Linux:** Автоматически создает два раздела на флешке (маленький FAT32 для загрузчика UEFI и огромный NTFS под данные).
* **Никакого дробления WIM:** Файл `install.wim` копируется монолитно, что гарантирует штатную работу оригинального установщика Microsoft и решает проблему «диски не найдены» при установке.

## 🛠 Зависимости
Для работы скрипта требуются стандартные утилиты разметки и форматирования. В большинстве дистрибутивов они уже установлены:
`sfdisk`, `mkfs.fat`, `mkfs.ntfs`, `ntfs-3g`, `rsync`, `parted`.

На **Debian / Ubuntu** их можно установить одной командой:
```bash
sudo apt install fdisk dosfstools ntfs-3g rsync parted
```

## 📦 Установка
Рекомендуется поместить скрипт в системную директорию для быстрого доступа:
```bash
sudo cp win-iso2usb /usr/local/sbin/win-iso2usb
sudo chmod +x /usr/local/sbin/win-iso2usb
sudo chown root:root /usr/local/sbin/win-iso2usb
```

## 💻 Использование
Запустите скрипт, передав ему путь к официальному ISO-образу и **целевой диск целиком** (например, `/dev/sdh`, а не отдельный раздел):

```bash
sudo win-iso2usb /путь/к/Windows.iso /dev/sdh
```

---
*Created by: Yuri A. Soshnikov (yas1972@yandex.ru)*  
*Modified & Fixed with AI Collaborator*


