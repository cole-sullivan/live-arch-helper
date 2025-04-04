#!/bin/sh

### FUNCTIONS ###

installpkg() {
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

setpass() {
	PASSWORD1=$(whiptail --nocancel --passwordbox "Enter root password." 10 60 3>&1 1>&2 2>&3 3>&1)
	PASSWORD2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$PASSWORD1" = "$PASSWORD2" ]; do
		unset PASSWORD2
		PASSWORD1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		PASSWORD2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	echo "$PASSWORD1" | passwd -s
}

installgpu() {
GPUBRAND=$(whiptail --title "GPU driver" --radiolist \
	"Use the arrow keys and space bar to select your GPU brand, then press Return or <OK> to continue." 20 78 4 \
	"Intel" "Install mesa & intel-media-driver" ON \
	"AMD" "Install mesa & libva-mesa-driver" OFF \
	"Nvidia" "Install nvidia & nvidia-utils" OFF 3>&1 1>&2 2>&3 3>&1) || error "User exited."
case "$GPUBRAND" in
	"Intel")
		for PACKAGE in mesa intel-media-driver; do
			whiptail --title "Installation" \
				--infobox "Installing \`$PACKAGE\` which is a required package." 8 70
			installpkg "$PACKAGE"
		done
		;;
	"AMD")
		for PACKAGE in mesa libva-mesa-driver; do
			whiptail --title "Installation" \
				--infobox "Installing \`$PACKAGE\` which is a required package." 8 70
			installpkg "$PACKAGE"
		done
		;;
	"Nvidia")
		for PACKAGE in nvidia nvidia-utils; do
			whiptail --title "Installation" \
				--infobox "Installing \`$PACKAGE\` which is a required package." 8 70
			installpkg "$PACKAGE"
		done
		;;
esac
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Set root password (user will have to enter this)
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
whiptail --title "Configuring bootloader" \
	--infobox "Setting up GRUB, the bootloader for this system." 8 70
rm -f /etc/mkinitcpio.conf
curl -LO -s https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/mkinitcpio.conf
chmod 644 mkinitcpio.conf
mv mkinitcpio.conf /etc/mkinitcpio.conf
mkinitcpio -p linux &>/dev/null

# Set locale
rm -f /etc/locale.gen
curl -LO -s https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/locale.gen
chmod 644 locale.gen
mv locale.gen /etc/locale.gen
locale-gen

# Configure grub
rm -f /etc/default/grub
curl -LO -s https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/grub
chmod 644 grub
mv grub /etc/default/grub
mkdir /boot/EFI
mount /dev/${1}p1 /boot/EFI
grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck &>/dev/null
cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null

# Enable services
systemctl enable NetworkManager

exit
