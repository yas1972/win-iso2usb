#!/bin/sh
#  Created: Yuri A. Soshnikov
#  Modified & Fixed: AI Collaborator
#  The author's email address: yas1972@yandex.ru

set -e

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
	echo "Error: This script must be run as root (using sudo)." >&2
	exit 1
fi

file_iso9660="$1"
dev_usb="$2"

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo "~$REAL_USER")

# Temporary mount points (no massive file copying to local drive)
base_tmp="$REAL_HOME/.tmp_win_usb_build"
iso_mnt_dir="$base_tmp/iso_source"
usb_boot_dir="$base_tmp/usb_boot"
usb_data_dir="$base_tmp/usb_data"

prepare_paths(){
	mkdir -p "$iso_mnt_dir" "$usb_boot_dir" "$usb_data_dir"
}

# --- CLEANUP FUNCTION (TRAP) ---
cleanup() {
	set +e
	echo "\n[CLEANUP] Cleaning up temporary mounts and files..."

	# Unmount directories in reverse order
	if mountpoint -q "$usb_boot_dir" 2>/dev/null; then umount -f "$usb_boot_dir" 2>/dev/null; fi
	if mountpoint -q "$usb_data_dir" 2>/dev/null; then umount -f "$usb_data_dir" 2>/dev/null; fi
	if mountpoint -q "$iso_mnt_dir" 2>/dev/null; then umount -f "$iso_mnt_dir" 2>/dev/null; fi

	if [ -d "$base_tmp" ]; then rm -Rf "$base_tmp" 2>/dev/null; fi
	echo "[CLEANUP] Done. System is clean."
}

# Trap signals for automatic cleanup on exit/interruption
trap cleanup EXIT INT TERM

# --- CHECK DEPENDENCIES ---
check_dependencies() {
	local missing=""
	for cmd in sfdisk mkfs.fat mkfs.ntfs stat rsync lsblk partprobe mount.ntfs-3g; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing="$missing $cmd"
		fi
	done

	if [ -n "$missing" ]; then
		echo "Error: Missing required tools:$missing" >&2
		echo "On Debian/Ubuntu: sudo apt install fdisk dosfstools ntfs-3g rsync parted" >&2
		trap - EXIT INT TERM
		exit 1
	fi
}

# --- DRIVE PROTECTION CHECK ---
check_drive_safety() {
	local dev="$1"
	if ! [ -b "$dev" ]; then
		echo "Error: Device $dev does not exist!" >&2
		trap - EXIT INT TERM
		exit 1
	fi

	# Prevent partition input (must be a whole drive letter)
	if echo "$dev" | grep -Eq '[0-9]+$'; then
		echo "Error: Please specify the WHOLE drive (e.g. /dev/sdh), NOT a partition." >&2
		trap - EXIT INT TERM
		exit 1
	fi

	# Prevent wiping critical system partitions
	local mounts=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null)
	for mp in $mounts; do
		case "$mp" in
			"/"|"/boot"|"/boot/efi"|"/home"|"/usr"|"/var")
				echo "CRITICAL ERROR: Device $dev contains active system mount point ($mp)!" >&2
				trap - EXIT INT TERM
				exit 1
				;;
		esac
	done
}

mountISOImage(){
	local iso9660_image="$1"
	echo "Mounting ISO image directly..."
	if [ ! -f "$iso9660_image" ]; then
		echo "Error: ISO file $iso9660_image not found!" >&2
		exit 1
	fi
	mount -t udf,iso9660 -o loop,ro "$iso9660_image" "$iso_mnt_dir"
}

prepareUSBdrive(){
	local parent_dev="$1"
	check_drive_safety "$parent_dev"

	echo "Preparing USB on $parent_dev using Rufus-like dual partition (MBR)..."
	umount "${parent_dev}"* 2>/dev/null || true

	# Wipe old partition tables and filesystem signatures to avoid conflicts
	dd if=/dev/zero of="$parent_dev" bs=512 count=4096 conv=notrunc status=none
	sync

	# Layout configuration: 
	# 1st partition: FAT32 (bootable, 64MB)
	# 2nd partition: NTFS (takes up the remaining free space)
	cat <<EOF | sfdisk --quiet "$parent_dev"
label: dos
2048, 131072, 0c, *
, -, 07
EOF

	echo "Informing kernel about partition changes..."
	sync
	partprobe "$parent_dev"
	sleep 3

	p1="${parent_dev}1"
	p2="${parent_dev}2"

	echo "Formatting partitions..."
	mkfs.fat -F32 -I -n "UEFI_BOOT" "$p1"
	mkfs.ntfs -f -L "WIN_DATA" "$p2"
}

copy_files_to_usb(){
	local parent_dev="$1"
	local p1="${parent_dev}1"  # FAT32
	local p2="${parent_dev}2"  # NTFS

	sync
	sleep 2

	echo "Mounting USB partitions..."
	
	# Mount NTFS via ntfs-3g for stable high-speed write operations
	if ! mount -t ntfs-3g "$p2" "$usb_data_dir"; then
		echo "CRITICAL ERROR: Failed to mount NTFS partition $p2!" >&2
		exit 1
	fi
	
	if ! mount "$p1" "$usb_boot_dir"; then
		echo "CRITICAL ERROR: Failed to mount FAT32 partition $p1!" >&2
		exit 1
	fi

	echo "Copying ALL data from ISO directly to NTFS partition (WIN_DATA)..."
	rsync -ah --info=progress2 "$iso_mnt_dir/" "$usb_data_dir/"

	echo "Copying UEFI boot files to FAT32 partition (UEFI_BOOT)..."
	mkdir -p "$usb_boot_dir/EFI/BOOT"
	if [ -d "$iso_mnt_dir/efi/boot" ]; then
		cp -Rf "$iso_mnt_dir/efi/boot/"* "$usb_boot_dir/EFI/BOOT/"
	elif [ -d "$iso_mnt_dir/EFI/BOOT" ]; then
		cp -Rf "$iso_mnt_dir/EFI/BOOT/"* "$usb_boot_dir/EFI/BOOT/"
	fi
	
	[ -f "$iso_mnt_dir/bootmgr.efi" ] && cp "$iso_mnt_dir/bootmgr.efi" "$usb_boot_dir/"

	echo "Syncing data to flash drive (please wait)..."
	sync
}

usage(){
	echo "Usage: $(basename "$0") <file.iso> <entire_usb_device (e.g. /dev/sdh)>"
}

# --- EXECUTION START ---
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
esac

# Validate target format (must look like /dev/sdX)
if echo "$dev_usb" | grep -Eq '^/dev/sd[a-z]$'; then
	mountISOImage "$file_iso9660"
else
	echo "Error: Invalid device format. Expected ENTIRE drive path like /dev/sdh (NOT /dev/sdh1)" >&2
	usage
	trap - EXIT INT TERM
	exit 1
fi

echo "Prepare a USB flash drive on $dev_usb? ALL DATA on the ENTIRE DRIVE will be LOST! (y/N)"
read -r answer < /dev/tty
case $answer in
	'Y'|'y')
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

copy_files_to_usb "$dev_usb"

echo "\nDone successfully! Your Rufus-like hybrid USB drive is ready."
exit 0
