########################iso2usb.sh################
#  Created: Yuri A. Soshnikov
#  The following functions are written using Google's AI: cleanup(),check_dependencies(),check_drive_safety()
#  The author's email address:yas1972@yandex.ru
#!/bin/sh

# Глобальные переменные
file_iso9660="$1"
dev_usb="$2"
tmpdir='/tmp/iso'
file_esd="install.esd"
file_wim="install.wim"
source='/tmp/iso/sources'
maxsizeFAT32=4294967296

# --- ФУНКЦИЯ ОЧИСТКИ (TRAP) ---
cleanup() {
    echo "\n[CLEANUP] Cleaning up temporary mounts and files..."

    # 1. Размонтируем ISO, если оно примонтировано
    if mountpoint -q /mnt/iso9660 2>/dev/null; then
        umount /mnt/iso9660 2>/dev/null
    fi
    if [ -d /mnt/iso9660 ]; then
        rmdir /mnt/iso9660 2>/dev/null
    fi

    # 2. Размонтируем флешку, если она примонтирована
    if mountpoint -q /tmp/USB 2>/dev/null; then
        umount /tmp/USB 2>/dev/null
    fi
    if [ -d /tmp/USB ]; then
        rmdir /tmp/USB 2>/dev/null
    fi

    # 3. Удаляем временные рабочие папки со всеми файлами
    rm -Rf "$tmpdir" /tmp/ESD 2>/dev/null

    echo "[CLEANUP] Done. System is clean."
}

# Регистрируем ловушку: выполнить cleanup при выходе (EXIT), Ctrl+C (INT) или завершении процесса (TERM)
trap cleanup EXIT INT TERM

# --- ПРОВЕРКА ЗАВИСИМОСТЕЙ ---
check_dependencies() {
    local missing=""
    # Перечисляем все утилиты, необходимые скрипту
    for cmd in wiminfo wimcapture wimsplit sfdisk mkfs.fat stat rsync lsblk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        echo "Error: Missing required tools:$missing" >&2
        echo "Please install them before running the script." >&2
        echo "On Debian/Ubuntu: sudo apt install wimtools fdisk dosfstools rsync" >&2
        # На время выполнения cleanup временно отключаем trap, чтобы не зацикливаться при жестком выходе
        trap - EXIT INT TERM
        exit 1
    fi
}

# --- ЗАЩИТА СИСТЕМНОГО ДИСКА ---
check_drive_safety() {
    local dev="$1"

    if ! [ -b "$dev" ]; then
        echo "Error: Device $dev does not exist!" >&2
        trap - EXIT INT TERM
        exit 1
    fi

    local mounts
    mounts=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null)

    for mp in $mounts; do
        case "$mp" in
            "/"|"/boot"|"/boot/efi"|"/home"|"/usr"|"/var")
                echo "CRITICAL ERROR: Device $dev contains active system mount point ($mp)!" >&2
                echo "Operation aborted to prevent system destruction." >&2
                trap - EXIT INT TERM
                exit 1
                ;;
        esac
    done
}

prepareISOImage(){
	local iso9660_image="$1"
	echo 'Prepare ISO image...'
	if ! [ -d "$tmpdir" ]; then
		mkdir -p "$tmpdir"
	fi

	if ! [ -d /mnt/iso9660/ ]; then
		mkdir -p /mnt/iso9660
	fi
	mount -t udf,iso9660 -o loop "$iso9660_image" /mnt/iso9660/
	cp -Rf /mnt/iso9660/* "$tmpdir/"
	chmod -R 644 "$tmpdir"/*
	umount /mnt/iso9660
	rmdir /mnt/iso9660
}

esd_to_wim(){
	local path_to_esd="$1"
	local path_to_wim="$2"
	if [ -f "$path_to_esd/$file_esd" ]; then
		wiminfo "$path_to_esd/$file_esd"
		echo 'Enter the image number:'
		read number_image
		wimcapture "$path_to_esd/$file_esd" "$path_to_wim/$file_wim" --index="$number_image"
	fi
}

size_of_file() {
	local name_of_file="$1"
	if [ -f "$name_of_file" ]; then
		stat -c %s "$name_of_file"
	else
		echo 0
	fi
}

split_esd(){
	echo 'Split install.wim or install.esd to install.swm and install2.swm...'
	if ! [ -d /tmp/ESD/ ]; then
		mkdir -p /tmp/ESD/
	fi
	if [ -f "$source/install.esd" ]; then
		mv "$source/install.esd" /tmp/ESD/
		esd_to_wim /tmp/ESD /tmp/ESD
	else
		mv "$source/install.wim" /tmp/ESD/
	fi
	cd /tmp/ESD || exit 1
	wimsplit "$file_wim" install.swm 4095
	cp install.swm install?.swm "$tmpdir/sources/"
	cd ..
	rm -f /tmp/ESD/*
	rmdir /tmp/ESD/
}

mountUSB(){
	echo 'Mounted flash drive...'
	local dev="$1"
	if ! [ -d /tmp/USB/ ]; then
		mkdir -p /tmp/USB/
	fi
	mount "$dev" /tmp/USB
}

prepareUSBdrive(){
	local dev="$1"
	check_drive_safety "$dev"

	local parent_dev
	parent_dev=$(echo "$dev" | sed 's/[0-9]*$//')

	echo "Preparing USB in $dev (Parent device: $parent_dev)..."

	# Размонтируем все разделы этой флешки перед форматированием
	umount "$parent_dev"* 2>/dev/null

	sfdisk --force --delete "$parent_dev"
	sfdisk --force --append "$parent_dev"
	mkfs.fat -F32 -I -v "$dev"
	fatlabel "$dev" ESD-USB
}

copy_esd_to_usb(){
	echo 'Copying ISO contents to ESD-USB...'
	if ! [ -d /tmp/USB/ ]; then
		echo "Error: Destination directory /tmp/USB/ does not exist!" >&2
		exit 1
	fi

	# Прогресс-бар вместо немого cp
	rsync -ah --info=progress2 "$tmpdir/" /tmp/USB/

	echo "Syncing data to flash drive (please wait)..."
	sync
}

usage(){
	echo "Usage: $(basename "$0") <file.iso> <device>"
}

# --- СТАРТ ВЫПОЛНЕНИЯ СКРИПТА ---

check_dependencies

# Валидация количества аргументов
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
	usage
	trap - EXIT INT TERM
	exit 1
fi

case $1 in
	""|--help|-h) usage; trap - EXIT INT TERM; exit 1;;
	*) ;;
esac

# Валидация формата диска
if echo "$dev_usb" | grep -Eq '^/dev/sd[a-z][0-9]?$'; then
	prepareISOImage "$file_iso9660"
else
	usage
	trap - EXIT INT TERM
	exit 1
fi

echo "Prepare a USB flash drive in $dev_usb? (Y/y/N/n)"
read answer
case $answer in
	'Y'|'y')
		prepareUSBdrive "$dev_usb"
		;;
	*)
		;;
esac

mountUSB "$dev_usb"

sizeESD=$(size_of_file "$source/$file_esd")
sizeWIM=$(size_of_file "$source/$file_wim")

if [ "$sizeESD" -gt "$maxsizeFAT32" ] || [ "$sizeWIM" -gt "$maxsizeFAT32" ]; then
	split_esd
fi

copy_esd_to_usb

# Убираем ловушку перед успешным финалом, так как cleanup вызовется сам по событию EXIT
echo "\nDone successfully! You can safely remove the USB drive."
exit 0
