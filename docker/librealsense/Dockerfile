# Prebuilt librealsense SDK source image (issue #97 / option B).
#
# librealsense is compiled ONCE per Ubuntu platform here and published to
# ghcr.io/ycpss91255-docker/librealsense:${LIBREALSENSE_VERSION}-${UBUNTU_CODENAME};
# the main repo Dockerfile then FROMs this image and COPYs the pre-built trees
# instead of recompiling librealsense (~15-25 min) on every CI run. The colcon
# wrapper (realsense-ros, which must compile against the SDK) still builds in
# the main image -- only the SDK is pre-baked here.
#
# librealsense2 is a pure C++ SDK -- it does NOT depend on ROS. Its only real
# axis is the Ubuntu platform: the compiled .so is ABI-bound to that release's
# glibc/libstdc++, so a jammy build cannot run on noble and vice versa. Hence
# the image is keyed on UBUNTU_CODENAME (not the ROS distro) and installs into
# the ROS-agnostic /usr/local prefix. TWO platforms publish from this same file:
#   jammy (Ubuntu 22.04, for ROS 2 humble) -> :${LIBREALSENSE_VERSION}-jammy
#   noble (Ubuntu 24.04, for ROS 2 jazzy)  -> :${LIBREALSENSE_VERSION}-noble
# The publish workflow (.github/workflows/build-librealsense.yaml) drives both
# via a codename x arch matrix.
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
ARG UBUNTU_CODENAME=jammy
ARG LIBREALSENSE_VERSION=v2.58.2

FROM ubuntu:${UBUNTU_CODENAME} AS build

ARG LIBREALSENSE_VERSION

SHELL ["/bin/bash", "-x", "-euo", "pipefail", "-c"]

# librealsense source-build deps (Intel's official Ubuntu list). Two things the
# leaner ubuntu:${UBUNTU_CODENAME} base needs that the old ros-base handled for
# us: ca-certificates (explicit -- ros-base pulled it in transitively; without
# it the https git clone below fails TLS), and DEBIAN_FRONTEND=noninteractive on
# the install (the GTK/GL deps pull in tzdata, whose postinst prompts for a
# timezone on this TTY-less build otherwise, wedging it indefinitely).
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
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

# Clone + compile librealsense at the pinned tag, install into the ROS-agnostic
# /usr/local prefix (the consumer's find_package(realsense2) resolves it from
# /usr/local -- a CMake default prefix -- and ldconfig registers /usr/local/lib
# via Ubuntu's /etc/ld.so.conf.d/libc.conf). FORCE_RSUSB_BACKEND=true =
# userspace backend (no kernel module -- required for the Pi). Python bindings
# stay OFF (pybind11 cannot inherit PYTHON_EXECUTABLE here). Two DESTDIR trees
# are produced: /rs-full (full) and /rs-stage (tools-pruned), so the consumer
# can COPY only librealsense files and never the base Ubuntu install.
RUN git clone --depth 1 --branch "${LIBREALSENSE_VERSION}" \
        https://github.com/IntelRealSense/librealsense.git /tmp/librealsense && \
    cmake -S /tmp/librealsense -B /tmp/librealsense/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="/usr/local" \
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
    rm -f /rs-stage/usr/local/bin/realsense-viewer && \
    rm -f /rs-stage/usr/local/bin/rs-* && \
    rm -f /rs-stage/usr/local/lib/librealsense2-gl.so* && \
    rm -rf /tmp/librealsense

############################## test ##############################
# Publish-time smoke GATE. This stage IS the correctness definition of the SDK
# image: the publish workflow builds `--target test` (push=false) BEFORE it
# pushes the `export` target, so a broken SDK tree never reaches GHCR. It runs
# against the `build` stage (which still carries the librealsense build-deps, so
# ldd can resolve the .so). Asserts, and hard-fails on any miss:
#   - both DESTDIR trees exist under /usr/local/lib
#   - /rs-full's librealsense2.so is present and fully linkable (no "not found")
#   - the versioned soname (librealsense2.so.*) is present in /rs-full
#   - /rs-stage is pruned: NO realsense-viewer, NO bin/rs-*, NO librealsense2-gl
FROM build AS test

# `build` sets this SHELL; re-declare it so hadolint's shellcheck sees bash
# (compgen) + pipefail (the ldd | grep pipe) in this stage's RUN.
SHELL ["/bin/bash", "-x", "-euo", "pipefail", "-c"]

RUN full_lib="/rs-full/usr/local/lib"; \
    stage_lib="/rs-stage/usr/local/lib"; \
    stage_bin="/rs-stage/usr/local/bin"; \
    fail() { echo "SDK TEST FAIL: $1" >&2; exit 1; }; \
    [[ -d "${full_lib}" ]] || fail "${full_lib} missing"; \
    [[ -d "${stage_lib}" ]] || fail "${stage_lib} missing"; \
    [[ -e "${full_lib}/librealsense2.so" ]] || fail "librealsense2.so missing in /rs-full"; \
    if ldd "${full_lib}/librealsense2.so" 2>&1 | grep -q "not found"; then \
        ldd "${full_lib}/librealsense2.so" || true; \
        fail "unresolved shared library in librealsense2.so"; \
    fi; \
    compgen -G "${full_lib}/librealsense2.so.*" >/dev/null || fail "versioned soname librealsense2.so.* missing in /rs-full"; \
    if [[ -e "${stage_bin}/realsense-viewer" ]]; then fail "realsense-viewer not pruned from /rs-stage"; fi; \
    if compgen -G "${stage_bin}/rs-*" >/dev/null; then fail "rs-* tools not pruned from /rs-stage"; fi; \
    if compgen -G "${stage_lib}/librealsense2-gl.so*" >/dev/null; then fail "librealsense2-gl not pruned from /rs-stage"; fi; \
    echo "SDK TEST OK: /rs-full linkable, versioned soname present, /rs-stage pruned"

############################## export ##############################
# The PUBLISHED image. A scratch image carrying ONLY the two librealsense trees
# -- the consumer (main Dockerfile) COPYs just /rs-full and /rs-stage, so the
# `build` stage's ROS base + build-deps were dead weight in the shipped image.
# Mirrors test-tools being a clean COPY-source. The publish workflow sets
# `target: export` on the build-and-push step.
FROM scratch AS export

COPY --from=build /rs-full /rs-full
COPY --from=build /rs-stage /rs-stage
