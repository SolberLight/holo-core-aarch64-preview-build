# Boot-test the image headless; exits early on QEMU death, login prompt, or panic.
param(
    [string]$Cpu = "neoverse-n1",
    [string]$Smp = "8",
    [string]$Thread = "multi",
    [int]$TimeoutMin = 6
)
$dir = $PSScriptRoot
# 8.3 path: Start-Process -ArgumentList does not re-quote args containing spaces
$qemuShort = "C:\PROGRA~1\qemu"
Get-Process qemu-system-aarch64 -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
Start-Sleep -Seconds 1
if (Test-Path "$dir\serial.log") { Remove-Item "$dir\serial.log" -Force -Confirm:$false }
Copy-Item "$qemuShort\share\edk2-arm-vars.fd" "$dir\efi_vars_test.fd" -Force

$args = @(
    "-M", "virt", "-cpu", $Cpu, "-smp", $Smp, "-m", "4096",
    "-accel", "tcg,thread=$Thread",
    "-drive", "if=pflash,format=raw,readonly=on,file=$qemuShort\share\edk2-aarch64-code.fd",
    "-drive", "if=pflash,format=raw,file=$dir\efi_vars_test.fd",
    "-drive", "if=virtio,format=qcow2,file=$dir\holo-arm.qcow2",
    "-nic", "user,model=virtio-net-pci",
    "-chardev", "file,id=con0,path=$dir\serial.log",
    "-device", "virtio-serial-pci", "-device", "virtconsole,chardev=con0",
    "-display", "none"
)
$p = Start-Process "$qemuShort\qemu-system-aarch64.exe" -PassThru -WindowStyle Hidden `
    -RedirectStandardError "$dir\qemu-stderr.log" -ArgumentList $args

$deadline = (Get-Date).AddMinutes($TimeoutMin)
$result = "TIMEOUT"
do {
    Start-Sleep -Seconds 10
    if ($p.HasExited) { $result = "QEMU_EXITED code=$($p.ExitCode)"; break }
    $raw = ""
    if (Test-Path "$dir\serial.log") {
        try { Copy-Item "$dir\serial.log" "$dir\serial-copy.log" -Force; $raw = [IO.File]::ReadAllText("$dir\serial-copy.log") } catch {}
    }
    if ($raw -match "login:") { $result = "LOGIN_PROMPT_REACHED"; break }
    if ($raw -match "Kernel panic") { $result = "KERNEL_PANIC"; break }
} until ((Get-Date) -gt $deadline)

Write-Output "RESULT: $result"
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -Confirm:$false; Write-Output "(qemu stopped)" }
if (Test-Path "$dir\qemu-stderr.log") {
    $err = Get-Content "$dir\qemu-stderr.log" -Tail 10
    if ($err) { Write-Output "--- qemu stderr ---"; $err }
}
