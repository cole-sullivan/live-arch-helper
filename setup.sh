#!/bin/sh

### FUNCTIONS ###

installpkg() {
	arch-chroot /mnt pacman --noconfirm --needed -S "$1" &>/dev/null
}

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
	# Partition disk into 3 parts
	whiptail --title "Partition disk" \
		--infobox "Partitioning $DISK for the installation of Arch Linux." 8 70
	(echo g; echo w) | fdisk /dev/$DISK &>/dev/null
	(echo n; echo 1; echo ""; echo +1G; echo n; echo 2; echo ""; echo +1G; echo n; echo 3; echo ""; echo ""; echo t; echo 3; echo 44; echo w) | fdisk /dev/$DISK &>/dev/null
}

formatpartitions() {
	# Format partitions and encrypt the third partition (where files will be stored)
	PASSPHRASE1=$(whiptail --nocancel --passwordbox "Enter a passphrase to use to encrypt your filesystem. You will use this passphrase to unlock your machine every time you boot your computer." 10 60 3>&1 1>&2 2>&3 3>&1)
	PASSPHRASE2=$(whiptail --nocancel --passwordbox "Retype passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$PASSPHRASE1" = "$PASSPHRASE2" ]; do
		unset PASSPHRASE2
		PASSPHRASE1=$(whiptail --nocancel --passwordbox "Passphrases do not match.\\n\\nEnter passphrase again." 10 60 3>&1 1>&2 2>&3 3>&1)
		PASSPHRASE2=$(whiptail --nocancel --passwordbox "Retype passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	whiptail --title "Format disk" \
		--infobox "Formatting and encrypting $DISK." 8 70
	mkfs.fat -F32 /dev/${DISK}p1 >/dev/null
	mkfs.ext4 -F /dev/${DISK}p2 &>/dev/null
	echo -n "$PASSPHRASE1" | cryptsetup luksFormat /dev/${DISK}p3 -d - &>/dev/null
	echo -n "$PASSPHRASE1" | cryptsetup open --type luks /dev/${DISK}p3 lvm -d -
	pvcreate /dev/mapper/lvm >/dev/null
	vgcreate volgroup0 /dev/mapper/lvm >/dev/null
	lvcreate -L 30GB volgroup0 -n lv_root >/dev/null
	lvcreate -l 100%FREE volgroup0 -n lv_home >/dev/null
	modprobe dm_mod
	vgscan >/dev/null
	vgchange -ay >/dev/null
	mkfs.ext4 -F /dev/volgroup0/lv_root &>/dev/null
	mkfs.ext4 -F /dev/volgroup0/lv_home &>/dev/null
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

setpass() {
	PASSWORD1=$(whiptail --nocancel --passwordbox "Enter root password." 10 60 3>&1 1>&2 2>&3 3>&1)
	PASSWORD2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$PASSWORD1" = "$PASSWORD2" ]; do
		unset PASSWORD2
		PASSWORD1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		PASSWORD2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	echo "$PASSWORD1" | arch-chroot /mnt passwd -s
}

installgpu() {
	GPUBRAND=$(whiptail --title "GPU driver" --radiolist \
		"Use the arrow keys and space bar to select your GPU brand, then press Return or <OK> to continue." 20 78 4 \
		"Intel" "Install mesa & intel-media-driver" ON \
		"AMD" "Install mesa & libva-mesa-driver" OFF \
		"Nvidia" "Install nvidia & nvidia-utils" OFF 3>&1 1>&2 2>&3 3>&1) || error "User exited."
  	whiptail --title "Installation" \
				--infobox "Installing $GPUBRAND GPU drivers for Arch." 8 70
	case "$GPUBRAND" in
		"Intel")
    			arch-chroot /mnt pacman --noconfirm --needed -S mesa intel-media-driver &>/dev/null
			;;
		"AMD")
  			arch-chroot /mnt pacman --noconfirm --needed -S mesa libva-mesa-driver &>/dev/null
			;;
		"Nvidia")
  			arch-chroot /mnt pacman --noconfirm --needed -S nvidia nvidia-utils &>/dev/null
			;;
	esac
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
(echo ""; echo "") | pacstrap -i /mnt base &>/dev/null

# Generate fstab.
genfstab -U -p /mnt >> /mnt/etc/fstab

# Set password
setpass || error "User exited."

# Install additional packages, the kernel, and firmware
for PACKAGE in base-devel dosfstools grub efibootmgr lvm2 mtools neovim networkmanager os-prober sof-firmware sudo linux linux-headers linux-firmware; do
	whiptail --title "Installation" \
		--infobox "Installing \`$PACKAGE\` which is a required package." 8 70
	installpkg "$PACKAGE"
done

# Install GPU driver
installgpu || error "User exited."

# Generate RAM disks
whiptail --title "Generating ramdisks" \
	--infobox "Creating initial ramdisk environment using mkinitcpio." 8 70
arch-chroot /mnt /bin/sh << EOF
	rm -f /etc/mkinitcpio.conf
	curl -LOs https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/mkinitcpio.conf
	chmod 644 mkinitcpio.conf
	mv mkinitcpio.conf /etc/mkinitcpio.conf
	mkinitcpio -p linux &>/dev/null
EOF

# Set locale
whiptail --title "Setting locale" \
	--infobox "Setting the system locale." 8 70
arch-chroot /mnt /bin/sh << EOF
	rm -f /etc/locale.gen
	curl -LOs https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/locale.gen
	chmod 644 locale.gen
	mv locale.gen /etc/locale.gen
	locale-gen &>/dev/null
EOF

# Set up GRUB
whiptail --title "Setting up bootloader" \
	--infobox "Configuring GRUB, the system bootloader, for use." 8 70
arch-chroot /mnt /bin/sh << EOF
	rm -f /etc/default/grub
	curl -LOs https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/grub
	chmod 644 grub
	mv grub /etc/default/grub
	mkdir /boot/EFI
	mount /dev/${DISK}p1 /boot/EFI
	grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck &>/dev/null
	cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
	grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
EOF

# Enable services
arch-chroot /mnt/bin/sh << EOF
	systemctl enable NetworkManager
EOF

# Unmount all partitions and exit live USB.
umount -a
finalize
reboot
