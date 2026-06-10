# Launch the Holo core aarch64 (preview) VM under QEMU full-system emulation.
# Usage: .\run-holo-vm.ps1            -> graphical window (virtio-gpu, login on tty1)
#        .\run-holo-vm.ps1 -Headless  -> text console (hvc0) in this terminal
#
# Notes:
# - CPU model neoverse-n1: this kernel boots fine on it and, unlike "max",
#   it has no pointer-authentication emulation (~10x boot slowdown on TCG).
# - The guest kernel has NO PL011 driver (Valve hardware-port config), so the
#   console must be virtio (hvc0), not -serial/ttyAMA0.
param([switch]$Headless)

$qemuDir = "C:\Program Files\qemu"
$qemu = Join-Path $qemuDir "qemu-system-aarch64.exe"
$dir = $PSScriptRoot

# Per-VM writable copy of the UEFI variable store
if (-not (Test-Path "$dir\efi_vars.fd")) {
    Copy-Item (Join-Path $qemuDir "share\edk2-arm-vars.fd") "$dir\efi_vars.fd"
}

$qemuArgs = @(
    "-M", "virt",
    "-cpu", "neoverse-n1",
    "-smp", "8",
    "-m", "6144",
    "-accel", "tcg,thread=multi",
    "-drive", "if=pflash,format=raw,readonly=on,file=$qemuDir\share\edk2-aarch64-code.fd",
    "-drive", "if=pflash,format=raw,file=$dir\efi_vars.fd",
    "-drive", "if=none,id=disk0,format=qcow2,file=$dir\holo-arm.qcow2",
    "-device", "virtio-blk-pci,drive=disk0,bootindex=0",
    "-device", "qemu-xhci", "-device", "usb-kbd", "-device", "usb-tablet",
    "-nic", "user,model=virtio-net-pci,hostfwd=tcp::2222-:22",
    "-chardev", "stdio,id=con0",
    "-device", "virtio-serial-pci", "-device", "virtconsole,chardev=con0"
)

if ($Headless) {
    $qemuArgs += @("-display", "none")
} else {
    # GTK window + host<->guest clipboard bridge (needs spice-vdagent in the guest)
    $qemuArgs += @(
        "-device", "virtio-gpu-pci",
        "-display", "gtk,gl=off",
        "-chardev", "qemu-vdagent,id=vdagent,name=vdagent,clipboard=on",
        "-device", "virtserialport,chardev=vdagent,name=com.redhat.spice.0"
    )
}

& $qemu @qemuArgs
