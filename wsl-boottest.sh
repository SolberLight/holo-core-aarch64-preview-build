#!/bin/bash
# Boot-test holo-arm.qcow2 under Linux/WSL QEMU; early-exit on death/login/panic
set -e
WORK=/root/holo-build
OUT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK"
cp "$OUT/holo-arm.qcow2" "$WORK/test.qcow2"
cp /usr/share/AAVMF/AAVMF_VARS.fd "$WORK/vars.fd"
rm -f "$WORK/serial.log"

qemu-system-aarch64 \
  -M virt -cpu neoverse-n1 -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd \
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
