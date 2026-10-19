# win-iso2usb

A lightweight, fast, and secure POSIX sh script for creating bootable Windows USB flash drives from Linux. Developed as a reliable alternative to WoeUSB-ng.

## 🛡️ Features
* **Data Protection:** The script checks active mount points and will strictly refuse to format a drive if it contains root (`/`), `/home`, or other critical system directories.
* **Progress Indicator:** Instead of "silent" waiting with the `cp` command, it uses `rsync` to display real-time speed, percentage, and remaining time.
* **Auto-Cleanup (trap):** If you cancel the operation via Ctrl+C, the script will automatically unmount temporary folders and delete gigabytes of cache from `/tmp`.
* **FAT32 (UEFI) Support:** Automatically splits heavy WIM/ESD files (over 4 GB) into smaller parts using `wimsplit`.

## 📦 Dependencies
Before use, ensure the following packages are installed on your system:
`wimtools`, `fdisk` (`sfdisk`), `dosfstools` (`mkfs.fat`), `rsync`, `lsblk`,`parted`,`less`.

## 🚀 Installation & Usage
Copy the script to the system directory and make it executable:
```bash
sudo cp iso2usb.sh /usr/local/sbin/win-iso2usb
sudo chmod +x /usr/local/sbin/win-iso2usb
```

Run the utility as root:
```bash
sudo win-iso2usb <path_to_image.iso> <usb_device_partition, e.g. /dev/sdb1>
```
# win-iso2usb

Легковесный, быстрый и безопасный POSIX sh скрипт для создания загрузочных USB-флешек с Windows из-под операционных систем Linux. Разработан как надежная альтернатива WoeUSB-ng.

## 🛡️ Особенности
* **Защита данных:** Скрипт проверяет активные точки монтирования и наотрез откажется форматировать диск, если на нем находится корень (`/`), `/home` или другие системные директории.
* **Индикатор прогресса:** Вместо "молчаливого" ожидания с командой `cp` используется `rsync`, отображающий реальную скорость, проценты и оставшееся время.
* **Авто-очистка (trap):** В случае отмены операции по Ctrl+C скрипт автоматически размонтирует временные папки и удалит гигабайты кэша из `/tmp`.
* **Поддержка FAT32 (UEFI):** Автоматически разбивает тяжелые WIM/ESD файлы (более 4 ГБ) на части с помощью `wimsplit`.

## 📦 Зависимости
Перед использованием убедитесь, что в вашей системе установлены следующие пакеты:
`wimtools`, `fdisk` (`sfdisk`), `dosfstools` (`mkfs.fat`), `rsync`, `lsblk`,`parted`,`less`.

## 🚀 Установка и использование
Скопируйте скрипт в системную директорию и сделайте его исполняемым:
```bash
sudo cp iso2usb.sh /usr/local/sbin/win-iso2usb
sudo chmod +x /usr/local/sbin/win-iso2usb
```

Запустите утилиту от имени суперпользователя:
```bash
sudo win-iso2usb <путь_к_образу.iso> <устройство_флешки, например /dev/sdb>
```
