# Movie Battles II (MBII) GPU container
#
# i386 image that lets the 32-bit OpenJK-based MBII client render via the
# host NVIDIA driver over X11.
#
# The image contains NO NVIDIA files (freely redistributable): the driver's
# 32-bit user-space GL stack is provided at runtime from ./driver/usr/lib on
# the host, bind-mounted to /usr/lib/nvidia with LD_LIBRARY_PATH set.
# Populate it with ./fetch-driver.sh (pulls the version-matched .run from
# NVIDIA's own download servers). run.sh / run-logs.sh mount it.
#
# rootfs-overlay/usr/lib holds only free components: the glvnd GLX/GL
# dispatch and the patched SDL2/SDL3 (both zlib/MIT). The glvnd EGL vendor
# config just points at libEGL_nvidia.so.0, which comes from the mount.
#
# Build with the i386 platform:
#   podman build --platform linux/386 -t localhost/mbii-gpu .
FROM almalinux:10-kitten

RUN dnf -y install \
        SDL2 \
        mesa-libGL \
        libX11 \
        libXext \
        libXi \
        libXrandr \
        libXcursor \
        libXinerama \
        libXfixes \
        libxkbcommon \
        libXrender \
        zlib \
        libstdc++ \
        pipewire-libs \
    && dnf clean all

# Vendor only free components: patched libSDL3/libSDL2 and the glvnd GL/GLX
# dispatch (zlib/MIT). NVIDIA user-space libs come from the host mount
# /usr/lib/nvidia (see ./fetch-driver.sh), so this image is freely redistributable.
COPY rootfs-overlay/usr/lib/ /usr/lib/
COPY rootfs-overlay/usr/share/glvnd/ /usr/share/glvnd/

ENV __GLX_VENDOR_LIBRARY_NAME=nvidia
ENV LIBGL_ALWAYS_INDIRECT=0
