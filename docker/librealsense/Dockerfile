# Prebuilt librealsense SDK source image (issue #97 / option B).
#
# librealsense is compiled ONCE per ROS 2 distro here and published to
# ghcr.io/ycpss91255-docker/librealsense:${ROS_DISTRO}-${LIBREALSENSE_VERSION};
# the main repo Dockerfile then FROMs this image and COPYs the pre-built trees
# instead of recompiling librealsense (~15-25 min) on every CI run. The colcon
# wrapper (realsense-ros, which must compile against the SDK) still builds in
# the main image -- only the SDK is pre-baked here.
#
# TWO distros are published from the same file, parameterized by ROS_DISTRO:
#   humble (Ubuntu 22.04 jammy)  -> :humble-${LIBREALSENSE_VERSION}
#   jazzy  (Ubuntu 24.04 noble)  -> :jazzy-${LIBREALSENSE_VERSION}
# The publish workflow (.github/workflows/build-librealsense.yaml) drives both
# via a distro x arch matrix.
#
# This image is a BUILD-TIME SOURCE only (never shipped), so its size is
# irrelevant: it carries two DESTDIR trees the consumer COPYs librealsense
# files out of, WITHOUT dragging in the base ROS install.
#   /rs-full  -- full install: viewer + rs-* examples + librealsense2-gl
#   /rs-stage -- tools-pruned copy for the runtime overlay (viewer / rs-* / gl
#                removed), matching exactly what the old inline build staged.
#
# The cmake flag set and prune list are IDENTICAL to the source build that
# previously lived in the main Dockerfile's devel stage; keep them in sync if
# the pins ever move.
ARG ROS_DISTRO=humble
ARG LIBREALSENSE_VERSION=v2.58.2

FROM ros:${ROS_DISTRO}-ros-base AS build

ARG ROS_DISTRO
ARG LIBREALSENSE_VERSION

SHELL ["/bin/bash", "-x", "-euo", "pipefail", "-c"]

# librealsense source-build deps (Intel's official Ubuntu list) -- the same set
# the main Dockerfile's devel-base installs for the SDK compile.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        wget \
        cmake \
        build-essential \
        pkg-config \
        libssl-dev \
        libusb-1.0-0-dev \
        libudev-dev \
        libgtk-3-dev \
        libglfw3-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Clone + compile librealsense at the pinned tag, install into the ROS prefix
# (mirrors the apt layout the wrapper's find_package(realsense2) resolves).
# FORCE_RSUSB_BACKEND=true = userspace backend (no kernel module -- required
# for the Pi). Python bindings stay OFF (pybind11 cannot inherit
# PYTHON_EXECUTABLE here). Two DESTDIR trees are produced: /rs-full (full) and
# /rs-stage (tools-pruned), so the consumer can COPY only librealsense files
# and never the base ROS install.
RUN git clone --depth 1 --branch "${LIBREALSENSE_VERSION}" \
        https://github.com/IntelRealSense/librealsense.git /tmp/librealsense && \
    cmake -S /tmp/librealsense -B /tmp/librealsense/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="/opt/ros/${ROS_DISTRO}" \
        -DFORCE_RSUSB_BACKEND=true \
        -DBUILD_WITH_DDS=OFF \
        -DCHECK_FOR_UPDATES=OFF \
        -DBUILD_PYTHON_BINDINGS=false \
        -DBUILD_WITH_CUDA=false \
        -DBUILD_EXAMPLES=true \
        -DBUILD_GRAPHICAL_EXAMPLES=true && \
    cmake --build /tmp/librealsense/build -j"$(nproc)" && \
    DESTDIR=/rs-full cmake --install /tmp/librealsense/build && \
    cp -a /rs-full /rs-stage && \
    rm -f "/rs-stage/opt/ros/${ROS_DISTRO}/bin/realsense-viewer" && \
    rm -f /rs-stage/opt/ros/"${ROS_DISTRO}"/bin/rs-* && \
    rm -f /rs-stage/opt/ros/"${ROS_DISTRO}"/lib/librealsense2-gl.so* && \
    rm -rf /tmp/librealsense
