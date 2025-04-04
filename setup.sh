#!/bin/sh

### FUNCTIONS ###

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

welcomemsg() {
	whiptail --title "Welcome!" \
		--msgbox "Welcome to the live USB helper script for [INSERT NAME]!\\n\\nThis script will install Arch onto your machine and prepare it for the [INSERT NAME] installation script.\\n\\n" 10 60
	
	whiptail --title "Important Note!" --yes-button "All ready!" \
		--no-button "Exit script" \
		--yesno "Be sure the computer you are using is connected to the internet and you know the name of the disk you would like to use (i.e. /dev/nvme0n1).\\n\\n" 8 70
}

partitiondisk() {
	whiptail --title "Partition disk" \
		--infobox "Partitioning $DISK for the installation of Arch Linux." 8 70
	(echo g; echo w) | fdisk /dev/$DISK >/dev/null 2>&1
	(echo n; echo 1; echo ""; echo +1G; echo n; echo 2; echo ""; echo +1G; echo n; echo 3; echo ""; echo ""; echo t; echo 3; echo 44; echo w) | fdisk /dev/$DISK >/dev/null 2>&1
}

formatpartitions() {
	PASSPHRASE1=$(whiptail --nocancel --passwordbox "Enter a passphrase to use to encrypt your filesystem. You will use this passphrase to unlock your machine every time you boot your computer." 10 60 3>&1 1>&2 2>&3 3>&1)
	PASSPHRASE2=$(whiptail --nocancel --passwordbox "Retype passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$PASSPHRASE1" = "$PASSPHRASE2" ]; do
		unset PASSPHRASE2
		PASSPHRASE1=$(whiptail --nocancel --passwordbox "Passphrases do not match.\\n\\nEnter passphrase again." 10 60 3>&1 1>&2 2>&3 3>&1)
		PASSPHRASE2=$(whiptail --nocancel --passwordbox "Retype passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	whiptail --title "Format disk" \
		--infobox "Formatting and encrypting $DISK." 8 70
	mkfs.fat -F32 /dev/${DISK}p1
	mkfs.ext4 /dev/${DISK}p2
	echo -n "$PASSPHRASE1" | cryptsetup luksFormat /dev/${DISK}p3 -d - &>/dev/null
	echo -n "$PASSPHRASE1" | cryptsetup open --type luks /dev/${DISK}p3 lvm -d -
	pvcreate /dev/mapper/lvm
	vgcreate volgroup0 /dev/mapper/lvm
	lvcreate -L 30GB volgroup0 -n lv_root
	lvcreate -l 100%FREE volgroup0 -n lv_home
	modprobe dm_mod
	vgscan
	vgchange -ay
	mkfs.ext4 /dev/volgroup0/lv_root
	mkfs.ext4 /dev/volgroup0/lv_home
}

mountpartitions() {
	whiptail --title "Mounting parititions" \
		--infobox "Mounting the newly formatted partitions so that they can be accessed." 8 70
	mount /dev/volgroup0/lv_root /mnt
	mkdir /mnt/boot
	mount /dev/${DISK}p2 /mnt/boot
	mkdir /mnt/home
	mount /dev/volgroup0/lv_home /mnt/home
}

finalize() {
        whiptail --title "All done!" \
		--msgbox "Provided there were no hidden errors, the script completed successfully and Arch Linux has been installed.\\n\\nSelect <OK> to reboot the machine.\\n\\n" 13 80
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Welcome user.
welcomemsg || error "User exited."

# Get disk name.
DISK=$(whiptail --inputbox "First, please enter the name of the disk you would like to install Arch Linux on (i.e. /dev/_____, enter the blank)." 10 60 3>&1 1>&2 2>&3 3>&1) || error "User exited."

# Partition disk.
partitiondisk || error "User exited."

# Format partitions.
formatpartitions || error "User exited."

# Mount partitions.
mountpartitions || error "User exited."

# Install base packages.
whiptail --title "Installation" \
	--infobox "Installing base packages to the new root partition." 8 70
pacstrap -i /mnt base >/dev/null

# Generate fstab.
genfstab -U -p /mnt >> /mnt/etc/fstab

# Enter system and finish setup.
arch-chroot /mnt curl -LO https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/root.sh
arch-chroot /mnt sh root.sh $DISK

# Unmount all partitions and exit live USB.
umount -a
finalize
reboot
