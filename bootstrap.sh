# Build an Arch/holo aarch64 rootfs tarball inside the Valve base container.
# Run via:
#   docker run --platform linux/arm64 --rm --privileged \
#     -v <workdir>:/out -v holopkgcache:/rootfs/var/cache/pacman/pkg \
#     registry.gitlab.steamos.cloud/holo/holo-core-aarch64-preview/base \
#     bash /out/bootstrap.sh [output.tar] [extra packages...]
set -ex
OUT_TAR="${1:-rootfs.tar}"
[ $# -gt 0 ] && shift
EXTRA_PKGS="$*"

pacman -Sy --noconfirm
mkdir -p /rootfs/var/lib/pacman /rootfs/proc /rootfs/sys /rootfs/dev
mount -t proc proc /rootfs/proc
mount --rbind /sys /rootfs/sys
mount --rbind /dev /rootfs/dev
pacman --root /rootfs --noconfirm -Sy base linux mkinitcpio networkmanager \
  openssh sudo nano htop less dosfstools e2fsprogs $EXTRA_PKGS
cp /etc/pacman.conf /rootfs/etc/pacman.conf
cp /etc/pacman.d/mirrorlist /rootfs/etc/pacman.d/mirrorlist
echo 'KEYMAP=us' > /rootfs/etc/vconsole.conf

# full-module initramfs: autodetect inside a container would miss virtio etc.
KVER=$(ls /rootfs/usr/lib/modules | head -1)
chroot /rootfs mkinitcpio -k "$KVER" -g /boot/initramfs-linux-fallback.img -S autodetect

ls -la /rootfs/boot
test -f /rootfs/boot/vmlinuz-linux
test -f /rootfs/boot/initramfs-linux-fallback.img
test -f /rootfs/usr/lib/systemd/boot/efi/systemd-bootaa64.efi
umount -R /rootfs/dev /rootfs/sys /rootfs/proc
tar --numeric-owner --xattrs \
  --exclude='./var/cache/pacman/pkg/*' \
  --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/*' \
  -cpf "/out/$OUT_TAR" -C /rootfs .
echo BOOTSTRAP_DONE
