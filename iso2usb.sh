#!/bin/sh
#  Created: Yuri A. Soshnikov
#  The following functions are written using Google's AI: cleanup(),check_dependencies(),check_drive_safety()
#  The author's email address:yas1972@yandex.ru

# Глобальные переменные
file_iso9660="$1"
dev_usb="$2"

# Временные директории перенесены на жесткий диск
esd_dir="$HOME/.tmp/esd"
tmpdir="$HOME/.tmp/iso"
usb_dir="$HOME/.tmp/usb"
source="$HOME/.tmp/iso/sources"

file_esd="install.esd"
file_wim="install.wim"
maxsizeFAT32=4294967296

prepare_paths(){
	mkdir -p "$esd_dir" "$tmpdir" "$source" "$usb_dir"
}

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
	if mountpoint -q "$usb_dir" 2>/dev/null; then
		umount "$usb_dir" 2>/dev/null
	fi

	# 3. Полностью удаляем временную скрытую папку со всем мусором
	if [ -d "$HOME/.tmp" ]; then
		rm -Rf "$HOME/.tmp" 2>/dev/null
	fi

	echo "[CLEANUP] Done. System is clean."
}

# Регистрируем ловушку: выполнить cleanup при выходе (EXIT), Ctrl+C (INT) или завершении процесса (TERM)
trap cleanup EXIT INT TERM

# --- ПРОВЕРКА ЗАВИСИМОСТЕЙ ---
check_dependencies() {
	local missing=""
	for cmd in wiminfo wimexport wimsplit sfdisk mkfs.fat stat rsync lsblk; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing="$missing $cmd"
		fi
	done

	if [ -n "$missing" ]; then
		echo "Error: Missing required tools:$missing" >&2
		echo "Please install them before running the script." >&2
		echo "On Debian/Ubuntu: sudo apt install wimtools fdisk dosfstools rsync" >&2
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
		wimexport "$path_to_esd/$file_esd" "$number_image" "$path_to_wim/$file_wim" --compress=LZX
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
	
	# ИСПРАВЛЕНО: Теперь работаем в $esd_dir на жестком диске, а не в /tmp
	if [ -f "$source/install.esd" ]; then
		mv "$source/install.esd" "$esd_dir/"
		esd_to_wim "$esd_dir" "$esd_dir"
	else
		mv "$source/install.wim" "$esd_dir/"
	fi
	
	cd "$esd_dir" || exit 1
	wimsplit "$file_wim" install.swm 4095
	cp -f install*.swm "$tmpdir/sources/"
	cd - >/dev/null || exit 1
}

mountUSB(){
	echo 'Mounted flash drive...'
	local dev="$1"
	# ИСПРАВЛЕНО: Монтируем в созданную $usb_dir
	mount "$dev" "$usb_dir"
}

prepareUSBdrive(){
	local dev="$1"
	check_drive_safety "$dev"

	local parent_dev
	parent_dev=$(echo "$dev" | sed 's/[0-9]*$//')

	echo "Preparing USB in $dev (Parent device: $parent_dev)..."

	umount "$parent_dev"* 2>/dev/null

	sfdisk --force --delete "$parent_dev"
	sfdisk --force --append "$parent_dev"
	mkfs.fat -F32 -I -v "$dev"
	fatlabel "$dev" ESD-USB
}

copy_esd_to_usb(){
	echo 'Copying ISO contents to ESD-USB...'
	if ! [ -d "$usb_dir" ]; then
		echo "Error: Destination directory $usb_dir does not exist!" >&2
		exit 1
	fi

	# ИСПРАВЛЕНО: Копируем rsync'ом в правильную папку $usb_dir
	rsync -ah --info=progress2 "$tmpdir/" "$usb_dir/"

	echo "Syncing data to flash drive (please wait)..."
	sync
}

usage(){
	echo "Usage: $(basename "$0") <file.iso> <device>"
}

# --- СТАРТ ВЫПОЛНЕНИЯ СКРИПТА ---

check_dependencies
prepare_paths

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
	usage
	trap - EXIT INT TERM
	exit 1
fi

case $1 in
	""|--help|-h) usage; trap - EXIT INT TERM; exit 1;;
	*) ;;
# --- СТАРТ ВЫПОЛНЕНИЯ СКРИПТА ---


check_dependencies
prepare_paths
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
