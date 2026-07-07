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

############################## test (publish gate) ##############################
# Publish-time smoke gate. A librealsense SDK image that fails these asserts
# must never be pushed, so this stage IS the correctness contract of the two
# DESTDIR trees the consumer COPYs. The publish workflow builds `--target test`
# (push=false) BEFORE it pushes the `export` image; see
# .github/workflows/build-librealsense.yaml.
FROM build AS test

ARG ROS_DISTRO

# `set -eux`: any failed assert aborts the build (non-zero RUN) -> the gate
# blocks the push. Each check maps to a property the consumer relies on.
RUN set -eux; \
    lib_full="/rs-full/opt/ros/${ROS_DISTRO}/lib"; \
    lib_stage="/rs-stage/opt/ros/${ROS_DISTRO}/lib"; \
    bin_stage="/rs-stage/opt/ros/${ROS_DISTRO}/bin"; \
    # (1) Both DESTDIR trees exist with a populated lib dir under the ROS prefix.
    test -d "${lib_full}"; \
    test -d "${lib_stage}"; \
    # (2) The core SDK shared object is present in the full tree ...
    test -f "${lib_full}/librealsense2.so"; \
    # ... and every one of its shared-library deps resolves (no "not found").
    ldd_out="$(ldd "${lib_full}/librealsense2.so" 2>&1)"; \
    echo "${ldd_out}"; \
    case "${ldd_out}" in \
        *"not found"*) \
            echo "SDK TEST FAIL: unresolved shared library in librealsense2.so" >&2; \
            exit 1 ;; \
    esac; \
    # (3) The versioned soname (librealsense2.so.<major.minor>) is present.
    soname="$(find "${lib_full}" -maxdepth 1 -name 'librealsense2.so.*' -print -quit)"; \
    test -n "${soname}"; \
    # (4) /rs-stage is the runtime-pruned tree: NO GUI viewer, NO rs-* example
    # binaries, NO GL helper library (all only belong in the devel overlay).
    test ! -e "${bin_stage}/realsense-viewer"; \
    leaked_rs="$(find "${bin_stage}" -maxdepth 1 -name 'rs-*' -print -quit 2>/dev/null || true)"; \
    if [ -n "${leaked_rs}" ]; then \
        echo "SDK TEST FAIL: rs-* example tools leaked into /rs-stage" >&2; \
        exit 1; \
    fi; \
    leaked_gl="$(find "${lib_stage}" -maxdepth 1 -name 'librealsense2-gl.so*' -print -quit 2>/dev/null || true)"; \
    if [ -n "${leaked_gl}" ]; then \
        echo "SDK TEST FAIL: librealsense2-gl leaked into /rs-stage" >&2; \
        exit 1; \
    fi; \
    echo "SDK TEST OK: /rs-full + /rs-stage trees validated"

############################## export (published image) ##############################
# The PUBLISHED image is literally just the two librealsense DESTDIR trees on
# `scratch`. The consumer only ever COPYs /rs-full and /rs-stage out of this
# image, so shipping the ros-base + build toolchain underneath was dead weight;
# this mirrors base's test-tools image being a clean COPY-source. Built with
# `--target export` on the build-and-push step of the publish workflow.
FROM scratch AS export

COPY --from=build /rs-full /rs-full
COPY --from=build /rs-stage /rs-stage
