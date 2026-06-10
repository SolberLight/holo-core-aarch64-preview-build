# holo-core-aarch64-preview-build

Build scripts that turn **Valve's public SteamOS/Arch Linux aarch64 preview**
package repository ([holo-core-aarch64-preview](https://holo-packages.steamos.cloud/holo-core-aarch64-preview))
into bootable disk images:

- a **QEMU virtual machine** image you can run on any x86_64 PC (full ARM emulation), and
- a **flashable raw image** for real ARM hardware (UEFI boot).

Prebuilt images are available on the
[Releases page](https://github.com/SolberLight/holo-core-aarch64-preview-build/releases);
the instructions below reproduce them from scratch.

`holo-core-aarch64-preview` is the open-source foundation that SteamOS for ARM
(the Steam Frame headset OS) is built on: Arch Linux packaging rebuilt for
`aarch64` by Valve and Collabora, published as a technology preview.

## What this repo does and does not contain

This repo contains **only build scripts and documentation** — no Valve files,
no Arch packages, no prebuilt images. Everything Valve-made is downloaded at
build time from Valve's public infrastructure:

| Upstream piece | Where the build gets it |
|---|---|
| Package sources (PKGBUILDs, reference) | <https://gitlab.steamos.cloud/holo/holo-core-aarch64-preview> |
| Binary pacman repo (`core` + `extra`) | <https://holo-packages.steamos.cloud/holo-core-aarch64-preview> |
| Base build container | `registry.gitlab.steamos.cloud/holo/holo-core-aarch64-preview/base` |

The resulting images are **plain Arch Linux ARM systems built from Valve's
package set**. They do **not** include Steam, SteamVR, or the Steam Frame
interface — those are proprietary and not part of the public preview. What you
get is the same OS base layer (same kernel build, same userland) with pacman
pointed at Valve's preview repos.

## Requirements

Scripts were developed on Windows 11; everything also works on a plain Linux
host (skip the WSL wrapper and run the `.sh` scripts directly as root).

- **Docker** able to run `linux/arm64` containers.
  On x86_64 install the binfmt handlers first:
  `docker run --rm --privileged tonistiigi/binfmt --install arm64`
- **A Linux environment with loop-device support** for image assembly
  (WSL2 Ubuntu on Windows; any distro natively) with
  `parted dosfstools e2fsprogs qemu-utils` installed.
- **QEMU** to run/test the VM. On Windows install a **stable release**:
  `winget install --id SoftwareFreedomConservancy.QEMU --version 10.1.0`
  (the default winget channel may give you a development snapshot — see
  Troubleshooting #5).

## Building

All commands run from a working directory containing these scripts
(artifacts land next to them).

### 1. Bootstrap the rootfs (Docker, emulated arm64 container)

```powershell
# QEMU VM rootfs (no firmware blobs needed in a VM):
docker run --platform linux/arm64 --rm --privileged `
  -v ${PWD}:/out -v holopkgcache:/rootfs/var/cache/pacman/pkg `
  registry.gitlab.steamos.cloud/holo/holo-core-aarch64-preview/base `
  bash /out/bootstrap.sh rootfs.tar

# Hardware rootfs (adds firmware + efibootmgr):
docker run --platform linux/arm64 --rm --privileged `
  -v ${PWD}:/out -v holopkgcache:/rootfs/var/cache/pacman/pkg `
  registry.gitlab.steamos.cloud/holo/holo-core-aarch64-preview/base `
  bash /out/bootstrap.sh rootfs-hw.tar linux-firmware efibootmgr
```

The named volume `holopkgcache` keeps downloaded packages between runs.
Add more packages as extra arguments if you want them baked in.

### 2. Assemble the disk image (WSL2 / Linux, as root)

```powershell
wsl -d Ubuntu -u root -- bash ./assemble.sh      # -> holo-arm.qcow2 (VM)
wsl -d Ubuntu -u root -- bash ./assemble-hw.sh   # -> holo-arm-hw.img (raw, 8 GiB)
```

Both produce a GPT/UEFI disk: 512 MiB FAT32 ESP (mounted at `/boot`,
systemd-boot as `\EFI\BOOT\BOOTAA64.EFI`) + ext4 root. The hardware image is
written to the Linux side (`/root/holo-build/`); compress it for distribution
with `xz -T0 holo-arm-hw.img`.

### 3. Run / verify

```powershell
.\run-holo-vm.ps1            # graphical window (login on tty1)
.\run-holo-vm.ps1 -Headless  # text console (virtio hvc0) in the terminal
.\boottest.ps1               # automated headless check -> RESULT: LOGIN_PROMPT_REACHED
```

- Login: `root` / `holo` — **change it**. SSH: `ssh -p 2222 root@localhost`.
- Boot takes ~2–5 minutes under emulation.
- GUI mode bridges the host clipboard (`qemu-vdagent`); install `spice-vdagent`
  in the guest to use it. For a desktop, `pacman -S plasma-desktop sddm` +
  `systemctl enable sddm` works — expect software rendering and low FPS
  under emulation.
- `ci-boottest.sh` / `ci-hwtest.sh` are the equivalent checks for Linux/WSL
  and the CI pipeline (the hardware image has no serial console, so it is
  probed over SSH). They exit non-zero unless a login is reached.

## Installing on an ARM device

```
xz -d holo-arm-hw.img.xz
# then flash holo-arm-hw.img with balenaEtcher, Rufus, or:
dd if=holo-arm-hw.img of=/dev/sdX bs=4M status=progress
```

Reality check before you flash:

- The kernel is Valve's **generic Arch build** — it boots hardware supported
  by mainline Linux. Devices needing vendor kernels/device trees (Raspberry
  Pi via its native boot path, most Qualcomm devices, phones) will not boot
  this image as-is. UEFI-capable hardware (SystemReady SBCs/servers, U-Boot
  with EFI, Apple Silicon VMs, Ampere, many Snapdragon-X laptops with caveats)
  is the target.
- The image is 8 GiB; after first boot grow the root partition
  (`parted /dev/... resizepart 2 100%` + `resize2fs`).
- Wi-Fi: `nmtui` (NetworkManager). Firmware blobs are included via
  `linux-firmware`.
- It cannot be installed on a Steam Frame: the Frame uses a signed,
  device-specific boot chain and kernel, and its Steam/VR UI is not public.

## Automated builds (GitHub Actions)

[`build-release.yml`](.github/workflows/build-release.yml) keeps releases in
sync with Valve's repositories without any external infrastructure:

- A cron job (every 6 h) probes upstream for changes: the base container's
  manifest digest (catches new snapshots — the snapshot URL is baked into the
  container) and the SHA256 of the pacman `core.db`/`extra.db` (catches
  package updates within a snapshot). Last-seen values live in
  [`state.json`](state.json), updated by the workflow after each release.
- On change (or a manual `workflow_dispatch` with `force`), a native
  **`ubuntu-24.04-arm`** runner rebuilds both images with the exact same
  scripts documented above — no emulation involved.
- Both images must pass automated boot verification (`ci-boottest.sh` serial
  watch + `ci-hwtest.sh` SSH probe) before anything is published.
- A release tagged `build-<snapshot>-r<run>` is created with the images,
  `SHA256SUMS`, and provenance (snapshot URL, container digest, kernel
  version) in the notes, using the built-in `GITHUB_TOKEN`.

If Valve publishes a future preview under a different GitLab path, the
watcher simply goes quiet — update `BASE_IMAGE` in the workflow.

## Troubleshooting / hard-won quirks

1. **No serial output, ever, on QEMU's default `-serial` (ttyAMA0):** Valve's
   kernel config has **no PL011 UART driver**. Use a virtio console
   (`-device virtio-serial-pci -device virtconsole`, kernel arg
   `console=hvc0`) or the graphical tty1. This cost hours — the kernel was
   booting fine, silently.
2. **UEFI cannot load `vmlinuz-linux`:** the aarch64 kernel file is
   gzip-compressed. The assemble scripts place a decompressed copy at
   `/boot/Image` and install a pacman hook (`95-decompress-kernel.hook`)
   that refreshes it on kernel upgrades.
3. **`-cpu max` looks like a hang on TCG:** pointer-authentication emulation
   slows the kernel ~10x. Use `-cpu neoverse-n1`.
4. **initramfs must include all modules:** mkinitcpio's `autodetect` hook,
   run inside a build container, strips virtio drivers. The bootstrap builds
   `initramfs-linux-fallback.img` with `-S autodetect` and boots that.
5. **Use stable QEMU on Windows:** a winget dev snapshot (11.0.50) crashed
   silently at kernel handoff with multi-threaded TCG. Stable 10.1.0 works.
6. **arm64 containers suddenly failing with `exec format error`:** Docker
   Desktop can lose its binfmt registrations (e.g. after Resource Saver).
   Re-run `docker run --rm --privileged tonistiigi/binfmt --install arm64`.

## Licensing

The scripts in this repository are MIT-licensed (see `LICENSE`).
The software the built images contain (including the prebuilt release
images) comes from Valve's holo-core-aarch64-preview repositories and carries
the respective upstream open-source licenses — see
[Arch Linux RFC 40](https://rfc.archlinux.page/0040-license-package-sources/)
for the licensing work that makes the preview's packages redistributable.
This project is not affiliated with or endorsed by Valve. "Steam", "SteamOS"
and "Steam Frame" are trademarks of Valve Corporation.
