#!/bin/bash
# Assemble a flashable aarch64 UEFI disk image for real ARM hardware
# from rootfs-hw.tar (run as root in WSL2 / any Linux with loop devices).
# Output: holo-arm-hw.img (raw, 8 GiB sparse) in $WORK — compress/flash after.
set -ex
WORK=/root/holo-build
OUT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK"
cd "$WORK"

rm -f holo-arm-hw.img
truncate -s 8G holo-arm-hw.img
parted -s holo-arm-hw.img mklabel gpt mkpart ESP fat32 1MiB 513MiB set 1 esp on mkpart root ext4 513MiB 100%

LOOP=$(losetup --find --show -P holo-arm-hw.img)
sleep 1

mkfs.vfat -F32 -n HOLOBOOT "${LOOP}p1"
mkfs.ext4 -q -L holoroot "${LOOP}p2"

mkdir -p /mnt/holo
mount "${LOOP}p2" /mnt/holo
tar --numeric-owner --xattrs -xpf "$OUT/rootfs-hw.tar" -C /mnt/holo

# relocate /boot onto the ESP
mv /mnt/holo/boot /mnt/holo/boot.tmp
mkdir /mnt/holo/boot
mount "${LOOP}p1" /mnt/holo/boot
cp -r /mnt/holo/boot.tmp/* /mnt/holo/boot/
rm -rf /mnt/holo/boot.tmp

# systemd-boot as the removable-media default loader (\EFI\BOOT\BOOTAA64.EFI)
mkdir -p /mnt/holo/boot/EFI/BOOT /mnt/holo/boot/loader/entries
cp /mnt/holo/usr/lib/systemd/boot/efi/systemd-bootaa64.efi /mnt/holo/boot/EFI/BOOT/BOOTAA64.EFI

# aarch64 vmlinuz is gzip-compressed; UEFI needs the uncompressed PE Image
zcat /mnt/holo/boot/vmlinuz-linux > /mnt/holo/boot/Image

# keep /boot/Image fresh when the kernel is updated on the device
mkdir -p /mnt/holo/etc/pacman.d/hooks
cat > /mnt/holo/etc/pacman.d/hooks/95-decompress-kernel.hook <<'EOF'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Decompressing kernel to /boot/Image for systemd-boot...
When = PostTransaction
Exec = /bin/sh -c 'zcat /boot/vmlinuz-linux > /boot/Image'
EOF

ROOTPARTUUID=$(blkid -s PARTUUID -o value "${LOOP}p2")
BOOTPARTUUID=$(blkid -s PARTUUID -o value "${LOOP}p1")

cat > /mnt/holo/boot/loader/loader.conf <<EOF
default holo.conf
timeout 3
console-mode keep
EOF

cat > /mnt/holo/boot/loader/entries/holo.conf <<EOF
title   Holo core aarch64 (preview)
linux   /Image
initrd  /initramfs-linux-fallback.img
options root=PARTUUID=$ROOTPARTUUID rw console=tty1
EOF

cat > /mnt/holo/etc/fstab <<EOF
PARTUUID=$ROOTPARTUUID  /      ext4  rw,relatime  0 1
PARTUUID=$BOOTPARTUUID  /boot  vfat  rw,relatime  0 2
EOF

echo holo-arm > /mnt/holo/etc/hostname
echo "LANG=C.UTF-8" > /mnt/holo/etc/locale.conf
ln -sf /usr/share/zoneinfo/UTC /mnt/holo/etc/localtime
systemd-machine-id-setup --root=/mnt/holo

# root password: holo  (CHANGE AFTER FIRST LOGIN)
HASH=$(openssl passwd -6 holo)
sed -i "s|^root:[^:]*:|root:${HASH}:|" /mnt/holo/etc/shadow

mkdir -p /mnt/holo/etc/ssh/sshd_config.d
echo "PermitRootLogin yes" > /mnt/holo/etc/ssh/sshd_config.d/10-root.conf

systemctl --root=/mnt/holo enable NetworkManager sshd systemd-timesyncd

umount /mnt/holo/boot
umount /mnt/holo
losetup -d "$LOOP"
echo "HW_ASSEMBLY_DONE: $WORK/holo-arm-hw.img"
