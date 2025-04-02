#!/bin/sh

# Set root password (user will have to enter this)
passwd

# Install additional packages, the kernel, and firmware
pacman -S base-devel dosfstools grub efibootmgr lvm2 mtools neovim networkmanager os-prober sof-firmware sudo
pacman -S linux linux-headers linux-firmware
pacman -S mesa intel-media-driver

# Generate RAM disks
rm -f /etc/mkinitcpio.conf
curl -LO https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/mkinitcpio.conf
chmod 644 mkinitcpio.conf
mv mkinitcpio.conf /etc/mkinitcpio.conf
mkinitcpio -p linux

# Set locale
rm -f /etc/locale.gen
curl -LO https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/locale.gen
chmod 644 locale.gen
mv locale.gen /etc/locale.gen
locale-gen

# Configure grub
rm -f /etc/default/grub
curl -LO https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/grub
chmod 644 grub
mv grub /etc/default/grub
mkdir /boot/EFI
mount /dev/nvme0n1p1 /boot/EFI
grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck
cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager

exit
