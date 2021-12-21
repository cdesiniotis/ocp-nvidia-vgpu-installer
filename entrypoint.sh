#!/bin/sh

set -x

DRIVER_VERSION=${DRIVER_VERSION:?"Missing driver version"}
RUN_DIR=/run/nvidia

# Mount the driver rootfs into the run directory with the exception of sysfs.
_mount_rootfs() {
    echo "Mounting NVIDIA driver rootfs..."
    mount --make-runbindable /sys
    mount --make-private /sys
    mkdir -p ${RUN_DIR}/driver
    mount --rbind / ${RUN_DIR}/driver

    echo "Change device files security context for selinux compatibility"
    chcon -R -t container_file_t ${RUN_DIR}/driver/dev
}

# Unmount the driver rootfs from the run directory.
_unmount_rootfs() {
    echo "Unmounting NVIDIA driver rootfs..."
    if findmnt -r -o TARGET | grep "${RUN_DIR}/driver" > /dev/null; then
        umount -l -R ${RUN_DIR}/driver
    fi
}

_install_driver() {
    /root/nvidia/NVIDIA-Linux-x86_64-${DRIVER_VERSION}-vgpu-kvm.run --kernel-source-path=/usr/src/kernels/$(uname -r) --kernel-install-path=/lib/modules/$(uname -r)/kernel/drivers/video/ --ui=none --no-questions --tmpdir /root/tmp/ --no-systemd
}

# Currently _install_driver() takes care of loading nvidia modules. Just need to start necessary vgpu daemons
_load_driver() {
    /usr/bin/nvidia-vgpud &
    /usr/bin/nvidia-vgpu-mgr &
}

_unload_driver() {
    local rmmod_args=()
    local nvidia_deps=0
    local nvidia_refs=0
    local nvidia_vgpu_vfio_refs=0

    echo "Stopping NVIDIA vGPU Manager..."
    if [ -f /var/run/nvidia-vgpu-mgr/nvidia-vgpu-mgr.pid ]; then
        local pid=$(< /var/run/nvidia-vgpu-mgr/nvidia-vgpu-mgr.pid)

        kill -TERM "${pid}"
        for i in $(seq 1 50); do
            kill -0 "${pid}" 2> /dev/null || break
            sleep 0.1
        done
        if [ $i -eq 50 ]; then
            echo "Could not stop NVIDIA vGPU Manager" >&2
            return 1
        fi
    fi

    echo "Unloading NVIDIA driver kernel modules..."
    if [ -f /sys/module/nvidia_vgpu_vfio/refcnt ]; then
        nvidia_vgpu_vfio_refs=$(< /sys/module/nvidia_vgpu_vfio/refcnt)
        rmmod_args+=("nvidia_vgpu_vfio")
        ((++nvidia_deps))
    fi
    if [ -f /sys/module/nvidia/refcnt ]; then
        nvidia_refs=$(< /sys/module/nvidia/refcnt)
        rmmod_args+=("nvidia")
    fi

    # TODO: check if nvidia module is in use by checking refcnt

    if [ ${#rmmod_args[@]} -gt 0 ]; then
        rmmod ${rmmod_args[@]}
        if [ "$?" != "0" ]; then
            return 1
        fi
    fi
    return 0
}

_shutdown() {
    if _unload_driver; then
        _unmount_rootfs
        return 0
    fi
    return 1
}

if ! _unload_driver; then
    echo "Previous NVIDIA driver installation cannot be removed. Exiting"
    exit 1
fi

_install_driver
_load_driver
_mount_rootfs

echo "Done, now waiting for signal"
trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
trap "_shutdown" EXIT

while true; do sleep 15 ; /usr/bin/pgrep nvidia-vgpu-mgr ; if [ $? -ne 0 ] ; then echo "nvidia-vgpu-mgr is not running" && exit 1; fi; done
