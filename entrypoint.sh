#!/bin/sh


DRIVER_VERSION=${DRIVER_VERSION:?"Missing driver version"}

/usr/sbin/rmmod nvidia
/root/nvidia/NVIDIA-Linux-x86_64-${DRIVER_VERSION}-vgpu-kvm.run --kernel-source-path=/usr/src/kernels/$(uname -r) --kernel-install-path=/lib/modules/$(uname -r)/kernel/drivers/video/ --silent --tmpdir /root/tmp/ --no-systemd

/usr/bin/nvidia-vgpud &
/usr/bin/nvidia-vgpu-mgr &

while true; do sleep 15 ; /usr/bin/pgrep nvidia-vgpu-mgr ; if [ $? -ne 0 ] ; then echo "nvidia-vgpu-mgr is not running" && exit 1; fi; done
