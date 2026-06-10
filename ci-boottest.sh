#!/bin/bash
# Boot-test holo-arm.qcow2 under Linux QEMU (CI runner or WSL).
# Watches the virtio serial console; exits 0 only on a login prompt.
set -e
WORK="${WORK:-/root/holo-build}"
OUT="$(cd "$(dirname "$0")" && pwd)"
FW_CODE="${FW_CODE:-/usr/share/AAVMF/AAVMF_CODE.fd}"
FW_VARS="${FW_VARS:-/usr/share/AAVMF/AAVMF_VARS.fd}"
mkdir -p "$WORK"
cp "$OUT/holo-arm.qcow2" "$WORK/test.qcow2"
cp "$FW_VARS" "$WORK/vars.fd"
rm -f "$WORK/serial.log"

if [ -w /dev/kvm ]; then ACCEL=(-accel kvm -cpu host); else ACCEL=(-cpu neoverse-n1); fi

qemu-system-aarch64 \
  -M virt "${ACCEL[@]}" -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file="$FW_CODE" \
  -drive if=pflash,format=raw,file="$WORK/vars.fd" \
  -drive if=virtio,format=qcow2,file="$WORK/test.qcow2" \
  -nic user,model=virtio-net-pci \
  -chardev file,id=con0,path="$WORK/serial.log" \
  -device virtio-serial-pci -device virtconsole,chardev=con0 \
  -display none &
QPID=$!

RESULT=TIMEOUT
for i in $(seq 1 60); do
  sleep 10
  if ! kill -0 $QPID 2>/dev/null; then RESULT="QEMU_EXITED"; break; fi
  if grep -q 'login:' "$WORK/serial.log" 2>/dev/null; then RESULT="LOGIN_PROMPT_REACHED"; break; fi
  if grep -q 'Kernel panic' "$WORK/serial.log" 2>/dev/null; then RESULT="KERNEL_PANIC"; break; fi
done

echo "RESULT: $RESULT"
kill $QPID 2>/dev/null || true
echo "--- last serial output ---"
tail -c 2500 "$WORK/serial.log" || true
[ "$RESULT" = "LOGIN_PROMPT_REACHED" ]
