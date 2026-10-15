#!/bin/sh
#  Created: Yuri A. Soshnikov
#  Modified & Fixed: AI Collaborator
#  The author's email address: yas1972@yandex.ru

# Строгое завершение при критических ошибках команд разметки
set -e

# Проверка прав суперпользователя (root)
if [ "$(id -u)" -ne 0 ]; then
	echo "Error: This script must be run as root (using sudo)." >&2
	exit 1
fi

# Глобальные переменные
file_iso9660="$1"
dev_usb="$2"

# Определяем реального пользователя, который вызвал sudo, и его домашнюю папку
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo "~$REAL_USER")

# Временная папка на жестком диске/SSD, чтобы не переполнять ОЗУ через /tmp
base_tmp="$REAL_HOME/.tmp_win_usb_build"
esd_dir="$base_tmp/esd"
tmpdir="$base_tmp/iso"
usb_dir="$base_tmp/usb"
source="$tmpdir/sources"

file_esd="install.esd"
file_wim="install.wim"
maxsizeFAT32=4294967296

prepare_paths(){
	mkdir -p "$esd_dir" "$tmpdir" "$usb_dir"
}

# --- ФУНКЦИЯ ОЧИСТКИ (TRAP) ---
cleanup() {
	# Отключаем 'set -e' внутри cleanup, чтобы он гарантированно доработал до конца
	set +e
	echo "\n[CLEANUP] Cleaning up temporary mounts and files..."

	if mountpoint -q /mnt/iso9660 2>/dev/null; then
		umount -f /mnt/iso9660 2>/dev/null
	fi
	if [ -d /mnt/iso9660 ]; then
		rmdir /mnt/iso9660 2>/dev/null
	fi

	if mountpoint -q "$usb_dir" 2>/dev/null; then
		umount -f "$usb_dir" 2>/dev/null
	fi

	if [ -d "$base_tmp" ]; then
		rm -Rf "$base_tmp" 2>/dev/null
	fi

	echo "[CLEANUP] Done. System is clean."
}

# Ловушка для автоматического вызова очистки при любом исходе
trap cleanup EXIT INT TERM

# --- ПРОВЕРКА ЗАВИСИМОСТЕЙ ---
check_dependencies() {
	local missing=""
	# В список добавлен less
	for cmd in wiminfo wimexport wimsplit sfdisk mkfs.fat stat rsync lsblk partprobe fatlabel less; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing="$missing $cmd"
		fi
	done

	if [ -n "$missing" ]; then
		echo "Error: Missing required tools:$missing" >&2
		echo "Please install them before running the script." >&2
		echo "On Debian/Ubuntu: sudo apt install wimtools fdisk dosfstools rsync parted less" >&2
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
	mount -t udf,iso9660 -o loop,ro "$iso9660_image" /mnt/iso9660/
	cp -Rf /mnt/iso9660/* "$tmpdir/"
	chmod -R 755 "$tmpdir"
	umount /mnt/iso9660
	rmdir /mnt/iso9660
}

esd_to_wim(){
	local path_to_esd="$1"
	local path_to_wim="$2"
	if [ -f "$path_to_esd/$file_esd" ]; then
		echo "======================================================"
		echo " [INFO] View available Windows editions."
		echo " Use the arrows to scroll, 'q' to exit."
		echo "======================================================"
		sleep 1
		
		# -E: закрыть less при достижении конца, -X: оставить текст на экране
		wiminfo "$path_to_esd/$file_esd" | less -EX
		
		echo "\n======================================================"
		echo 'Enter the number of the desired image (Index):'
		# Чтение ввода строго из TTY, так как стандартный stdin может быть перенаправлен
		read -r number_image < /dev/tty
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
	
	if [ -f "$source/install.esd" ]; then
		mv "$source/install.esd" "$esd_dir/"
		esd_to_wim "$esd_dir" "$esd_dir"
		rm -f "$esd_dir/$file_esd"
	else
		mv "$source/install.wim" "$esd_dir/"
	fi
	
	cd "$esd_dir"
	# Исправлено: указан точный путь к файлу wim
	wimsplit "$esd_dir/$file_wim" install.swm 4000
	rm -f "$esd_dir/$file_wim"
	cp -f install*.swm "$source/"
	cd - >/dev/null
}

mountUSB(){
	echo 'Mounting flash drive...'
	local dev="$1"
	mount "$dev" "$usb_dir"
}

prepareUSBdrive(){
	local dev="$1"
	check_drive_safety "$dev"

	# Выделяем имя родительского диска (например, /dev/sdb из /dev/sdb1)
	local parent_dev
	parent_dev=$(echo "$dev" | sed 's/[0-9]*$//')

	if [ "$dev" = "$parent_dev" ]; then
		echo "Error: Please specify a partition (e.g. /dev/sdb1), not the whole drive." >&2
		trap - EXIT INT TERM
		exit 1
	fi

	echo "Preparing USB on $dev (Parent device: $parent_dev) using GPT..."

	# Размонтируем все разделы этого диска перед изменением таблиц
	umount "${parent_dev}"* 2>/dev/null || true

	# 1. Создаем чистую таблицу разделов GPT без интерактивных вопросов
	echo "label: gpt" | sfdisk --quiet "$parent_dev"
	
	# 2. Создаем один раздел на весь объем, тип: 'U' (Microsoft basic data) без вопросов
	echo ',,U' | sfdisk --quiet --no-reread "$parent_dev"
	
	# 3. Перечитываем таблицу разделов в ядре Linux, чтобы появилось устройство $dev
	echo "Informing kernel about partition changes..."
	partprobe "$parent_dev"
	sleep 1 

	# Форматирование созданного раздела в FAT32 и присвоение метки
	mkfs.fat -F32 -I "$dev"
	fatlabel "$dev" ESD-USB
}

copy_esd_to_usb(){
	echo 'Copying ISO contents to ESD-USB...'
	if ! [ -d "$usb_dir" ]; then
		echo "Error: Destination directory $usb_dir does not exist!" >&2
		exit 1
	fi

	rsync -ah --info=progress2 "$tmpdir/" "$usb_dir/"

	echo "Syncing data to flash drive (please wait)..."
	sync
}

usage(){
	echo "Usage: $(basename "$0") <file.iso> <partition_device_path (e.g. /dev/sdb1)>"
}

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

# Проверка формата диска (строго должен оканчиваться на цифру раздела, например sdb1)
if echo "$dev_usb" | grep -Eq '^/dev/sd[a-z][0-9]+$'; then
	prepareISOImage "$file_iso9660"
else
	echo "Error: Invalid device format. Expected partition like /dev/sdb1" >&2
	usage
	trap - EXIT INT TERM
	exit 1
fi

echo "Prepare a USB flash drive on $dev_usb? All data on $dev_usb will be LOST! (y/N)"
read -r answer < /dev/tty
case $answer in
	'Y'|'y')
		# Временно отключаем 'set -e', так как umount выше может вернуть не ноль
		set +e
		prepareUSBdrive "$dev_usb"
		set -e
		;;
	*)
		echo "Aborted by user."
		trap - EXIT INT TERM
		exit 0
		;;
esac

mountUSB "$dev_usb"

sizeESD=$(size_of_file "$source/$file_esd")
sizeWIM=$(size_of_file "$source/$file_wim")

if [ "$sizeESD" -gt "$maxsizeFAT32" ] || [ "$sizeWIM" -gt "$maxsizeFAT32" ]; then
	split_esd
fi

copy_esd_to_usb

echo "\nDone successfully! You can safely remove the USB drive."
exit 0
