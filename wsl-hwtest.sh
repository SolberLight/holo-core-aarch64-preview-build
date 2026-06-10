#!/bin/bash
# Verify the hardware image boots: run it in QEMU and probe sshd via NAT.
# (The hw image console is tty1, so there is no serial output to watch.)
set -e
WORK=/root/holo-build
cd "$WORK"
command -v sshpass >/dev/null || { DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sshpass >/dev/null; }
cp /usr/share/AAVMF/AAVMF_VARS.fd vars-hw.fd

qemu-system-aarch64 \
  -M virt -cpu neoverse-n1 -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd \
  -drive if=pflash,format=raw,file=vars-hw.fd \
  -drive if=virtio,format=raw,file=holo-arm-hw.img \
  -nic user,model=virtio-net-pci,hostfwd=tcp::2223-:22 \
  -display none &
QPID=$!

RESULT=TIMEOUT
for i in $(seq 1 48); do
  sleep 10
  if ! kill -0 $QPID 2>/dev/null; then RESULT="QEMU_EXITED"; break; fi
  if OUT=$(sshpass -p holo ssh -p 2223 -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
        root@localhost 'uname -a; head -2 /etc/os-release' 2>/dev/null); then
    RESULT="SSH_LOGIN_OK"
    echo "$OUT"
    break
  fi
done

echo "RESULT: $RESULT"
kill $QPID 2>/dev/null || true
