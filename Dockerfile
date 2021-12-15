ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG DRIVER_VERSION
ENV DRIVER_VERSION=$DRIVER_VERSION

RUN dnf -y install git make sudo gcc \
&& dnf clean all \
&& rm -rf /var/cache/dnf

RUN mkdir -p /root/nvidia
WORKDIR /root/nvidia
ADD NVIDIA-Linux-x86_64-${DRIVER_VERSION}-vgpu-kvm.run .
RUN chmod +x /root/nvidia/NVIDIA-Linux-x86_64-${DRIVER_VERSION}-vgpu-kvm.run
ADD entrypoint.sh .
RUN chmod +x /root/nvidia/entrypoint.sh

RUN mkdir -p /root/tmp
