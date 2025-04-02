#!/bin/sh

finalize() {
        echo "All done! Provided there were no hidden errors, the script completed successfully. Your machine will reboot in 5 seconds."
        sleep 5
}

# Partition disk
(echo g; echo w) | fdisk /dev/nvme0n1
(echo n; echo 1; echo ""; echo +1G; echo p; echo n; echo 2; echo ""; echo +1G; echo p; echo n; echo 3; echo ""; echo ""; echo t; echo 3; echo 44; echo p; echo w) | fdisk /dev/nvme0n1

# Format partitions
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.ext4 /dev/nvme0n1p2
cryptsetup luksFormat /dev/nvme0n1p3 # User needs to enter password 2x
cryptsetup open --type luks /dev/nvme0n1p3 lvm # User needs to enter password again
pvcreate /dev/mapper/lvm
vgcreate volgroup0 /dev/mapper/lvm
lvcreate -L 30GB volgroup0 -n lv_root
lvcreate -l 100%FREE volgroup0 -n lv_home
modprobe dm_mod
vgscan
vgchange -ay
mkfs.ext4 /dev/volgroup0/lv_root
mkfs.ext4 /dev/volgroup0/lv_home

# Mount partitions
mount /dev/volgroup0/lv_root /mnt
mkdir /mnt/boot
mount /dev/nvme0n1p2 /mnt/boot
mkdir /mnt/home
mount /dev/volgroup0/lv_home /mnt/home

# Install base packages
pacstrap -i /mnt base

# Generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab

# Enter system and finish setup
arch-chroot /mnt curl -LO https://raw.githubusercontent.com/cole-sullivan/live-arch-helper/main/root.sh
arch-chroot /mnt sh root.sh

# Unmount all partitions and exit live USB
umount -a

finalize
reboot
