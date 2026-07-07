ARG ROS_DISTRO="humble"
ARG ROS_TAG="ros-base"
ARG UBUNTU_CODENAME="jammy"
# librealsense SDK pin. Declared before the first FROM so the `rs_sdk` stage's
# FROM tag can reference it (FROM-line ARGs must be global or pre-FROM). The
# prebuilt per-distro SDK images (humble-${LIBREALSENSE_VERSION},
# jazzy-${LIBREALSENSE_VERSION}) are produced by
# .github/workflows/build-librealsense.yaml and consumed below via `rs_sdk`.
ARG LIBREALSENSE_VERSION="v2.58.2"
# Pre-built lint + bats tools image (ShellCheck, Hadolint, Bats + the
# bats-support/assert/mock extensions). Resolves to `test-tools:local` for the
# local `just build` flow (build.sh auto-builds it from
# .base/dockerfile/Dockerfile.test-tools) or to the multi-arch
# ghcr.io/ycpss91255-docker/test-tools:vX.Y.Z in CI. The image is multi-arch,
# so `FROM ${TEST_TOOLS_IMAGE}` resolves the matching variant per build
# platform -- that is what lets the arm64 build (#72) ship arm64 lint/bats
# binaries with no per-repo arch-aware download logic. Consuming this image
# (instead of self-building the tools) is the template's canonical pattern
# (Dockerfile.example); see the sibling app/ros1_bridge for the same setup.
ARG TEST_TOOLS_IMAGE="test-tools:local"
# Prebuilt librealsense SDK source image, mirroring TEST_TOOLS_IMAGE's
# dual-source pattern. Resolves to `librealsense:local` for the local
# `just build` / `./build.sh` flow (the pre-build hook
# script/hooks/pre/build.sh auto-builds it from docker/librealsense/Dockerfile
# when LIBREALSENSE_IMAGE is unset -> self-contained, no GHCR needed), or to
# the multi-arch ghcr.io/ycpss91255-docker/librealsense:${ROS_DISTRO}-${LIBREALSENSE_VERSION}
# in CI (main.yaml passes it as a build-arg so buildx PULLS the prebuilt SDK
# instead of recompiling librealsense ~15-25 min per run). Both the GHCR export
# image and the local image expose the two trees at /rs-full and /rs-stage.
ARG LIBREALSENSE_IMAGE="librealsense:local"

############################## rs_sdk ##############################
# Prebuilt librealsense SDK (issue #97 / option B). Compiled ONCE per distro by
# .github/workflows/build-librealsense.yaml and published to GHCR, so CI no
# longer recompiles librealsense (~15-25 min) on every run -- it just pulls the
# matching distro image and COPYs the pre-built trees into the wrapper build
# below. The image carries two DESTDIR trees: /rs-full (full SDK: viewer + rs-*
# + gl) and /rs-stage (tools-pruned, for the runtime overlay). Multi-arch, so
# the tag resolves the matching variant per build platform. The source is
# parameterized via LIBREALSENSE_IMAGE (see the ARG above): a local build FROMs
# librealsense:local, CI FROMs the GHCR tag.
# hadolint ignore=DL3006
FROM ${LIBREALSENSE_IMAGE} AS rs_sdk

############################## sys ##############################
FROM ros:${ROS_DISTRO}-${ROS_TAG}-${UBUNTU_CODENAME} AS sys

# base v0.41.0 build contract: compose / CI inject USER_NAME / USER_GROUP /
# USER_UID / USER_GID (not the legacy USER / GROUP / UID / GID). Declare the
# new names and alias the legacy ones from them so the rest of this stage's
# user-creation logic stays unchanged. Without this the injected build-args
# are dropped and the image is built as the default user, breaking `just run`
# (image HOME != compose's /home/${USER_NAME}/work mount).
ARG USER_NAME="user"
ARG USER_GROUP="user"
ARG USER_UID="1000"
ARG USER_GID="${USER_UID}"
ARG USER="${USER_NAME}"
ARG GROUP="${USER_GROUP}"
ARG UID="${USER_UID}"
ARG GID="${USER_GID}"
ARG SHELL="/bin/bash"
ARG HARDWARE="x86_64"
ENV HOME="/home/${USER}"

ENV NVIDIA_VISIBLE_DEVICES="all"
ENV NVIDIA_DRIVER_CAPABILITIES="all"

SHELL ["/bin/bash", "-x", "-euo", "pipefail", "-c"]

# Setup users and groups
RUN if getent group "${GID}" >/dev/null; then \
        existing_grp="$(getent group "${GID}" | cut -d: -f1)"; \
        if [ "${existing_grp}" != "${GROUP}" ]; then \
            groupmod -n "${GROUP}" "${existing_grp}"; \
        fi; \
    else \
        groupadd -g "${GID}" "${GROUP}"; \
    fi; \
    \
    if getent passwd "${UID}" >/dev/null; then \
        existing_user="$(getent passwd "${UID}" | cut -d: -f1)"; \
        if [ "${existing_user}" != "${USER}" ]; then \
            usermod -l "${USER}" "${existing_user}"; \
        fi; \
        usermod -g "${GID}" -s "${SHELL}" -d "${HOME}" -m "${USER}"; \
    elif id -u "${USER}" >/dev/null 2>&1; then \
        usermod -u "${UID}" -g "${GID}" -s "${SHELL}" -d "/home/${USER}" -m "${USER}"; \
    else \
        useradd -l -u "${UID}" -g "${GID}" -s "${SHELL}" -m "${USER}"; \
    fi; \
    \
    mkdir -p /etc/sudoers.d; \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USER}"; \
    chmod 0440 "/etc/sudoers.d/${USER}"

# Setup locale, timezone and replace apt urls (Taiwan mirror)
ENV TZ="Asia/Taipei"
ENV LC_ALL="en_US.UTF-8"
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"

ARG APT_MIRROR_UBUNTU="tw.archive.ubuntu.com"
RUN sed -i "s@archive.ubuntu.com@${APT_MIRROR_UBUNTU}@g" /etc/apt/sources.list || true && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        tzdata \
        locales && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    locale-gen "${LANG}" && \
    update-locale LANG="${LANG}" && \
    ln -snf /usr/share/zoneinfo/"${TZ}" /etc/localtime && echo "${TZ}" > /etc/timezone

############################## devel-base ##############################
FROM sys AS devel-base

ARG ROS_DISTRO
ARG UBUNTU_CODENAME

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        sudo \
        psmisc \
        htop \
        # Shell
        tmux \
        terminator \
        # base tools
        ca-certificates \
        software-properties-common \
        wget \
        curl \
        git \
        vim \
        tree \
        # python3 tools
        python3-pip \
        python3-dev \
        python3-setuptools \
        # ROS 2 auto complete
        bash-completion \
        python3-colcon-argcomplete \
        ros-${ROS_DISTRO}-ros2cli \
        # ROS 2 desktop (devel only): rviz2 + the Qt/OpenGL/X stack that GUI
        # tools such as realsense-viewer and rviz2 need. The runtime image
        # stays on ros-base (this is in devel-base, not the runtime branch).
        ros-${ROS_DISTRO}-desktop \
        # RealSense source-build deps (#97). librealsense + realsense-ros are
        # compiled from pinned source in the devel stage instead of apt, so the
        # ros-${ROS_DISTRO}-realsense2-* packages are gone from here; these are
        # Intel's official Ubuntu build-dep list plus colcon/rosdep for the
        # wrapper. The GUI libs (libgtk-3/glfw3/gl1-mesa/glu1-mesa) back the
        # devel-only -DBUILD_GRAPHICAL_EXAMPLES (realsense-viewer + rs-* tools).
        build-essential \
        cmake \
        pkg-config \
        libssl-dev \
        libusb-1.0-0-dev \
        libudev-dev \
        libgtk-3-dev \
        libglfw3-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        python3-colcon-common-extensions \
        python3-rosdep \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Intel RealSense D400 Series Dynamic Calibration Tool (librscalibrationtool):
# Intel.Realsense.DynamicCalibrator + Intel.Realsense.CustomRW.
#
# Installed via Intel's officially-documented direct-.deb method
# (`dpkg -i librscalibrationtool_<ver>_amd64.deb`, per the D400 Calibration
# Tools User Guide), which Intel lists as supported on Ubuntu 22.04 (jammy) AND
# 24.04 (noble). The .deb is a precompiled amd64 binary that declares no apt
# Depends and links only forward-compatible standard libs, so the single
# Intel-hosted .deb installs and runs on both jammy and noble -- Intel does not
# index the package in its noble apt repo, but the direct-.deb path is the same
# binary for every supported release. Its runtime libs are therefore installed
# explicitly here; libglut.so.3's provider differs by release (jammy: freeglut3,
# noble: libglut3.12) and libusb-1.0-0 resolves on noble through the t64
# package's Provides. arm64 is skipped -- Intel ships no arm64 build -- so the
# multi-arch image still builds.
ARG RS_CAL_VERSION="2.13.1.0"
RUN arch="$(dpkg --print-architecture)" && \
    if [ "${arch}" = "amd64" ]; then \
        case "${UBUNTU_CODENAME}" in \
            jammy) glut_pkg="freeglut3" ;; \
            *) glut_pkg="libglut3.12" ;; \
        esac && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            libgl1 \
            libglu1-mesa \
            libusb-1.0-0 \
            libudev1 \
            "${glut_pkg}" && \
        # The Dynamic Calibrator links the SONAME libglut.so.3. jammy's
        # freeglut3 ships that symlink; noble's libglut3.12 ships only
        # libglut.so.3.12, so the jammy-built binary cannot resolve it on
        # noble. Create the SONAME link to the installed lib (freeglut's GLUT
        # API is ABI-stable across the soname bump). The amd64-only guard fixes
        # the x86_64 multiarch dir; jammy already provides libglut.so.3.
        if [ "${UBUNTU_CODENAME}" != "jammy" ]; then \
            ln -sf libglut.so.3.12 /usr/lib/x86_64-linux-gnu/libglut.so.3 && \
            ldconfig; \
        fi && \
        curl -fsSL "https://librealsense.intel.com/Debian/apt-repo/pool/jammy/main/librscalibrationtool_${RS_CAL_VERSION}_amd64.deb" \
            -o /tmp/librscalibrationtool.deb && \
        dpkg -i /tmp/librscalibrationtool.deb && \
        rm -f /tmp/librscalibrationtool.deb && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo "Skipping librscalibrationtool: Intel ships no ${arch} build"; \
    fi

############################## devel ##############################
FROM devel-base AS devel

# ROS_DISTRO is declared per-stage in a multi-stage build; without re-declaring
# it here the ${ROS_DISTRO} expansions below (install prefix, colcon rosdistro,
# staging paths) would be empty and the SDK/wrapper would land in /opt/ros//
# (#97).
ARG ROS_DISTRO

ARG USER_NAME="user"
ARG USER_GROUP="user"
ARG USER="${USER_NAME}"
ARG GROUP="${USER_GROUP}"
ARG ENTRYPOINT_FILE="script/entrypoint.sh"
ARG CONFIG_DIR="/tmp/config"
ARG SETUP_DIR="/tmp/setup"
ARG CONFIG_SRC="config"

# The realsense-ros wrapper pin (#97). Pinned, distro-agnostic (the same tag
# builds on humble+jazzy), and --build-arg overridable. Placed immediately
# before the wrapper build RUN so edits above stay buildx-cache-hot and only a
# version bump recompiles. NOT floating `latest` -- reproducible builds. The
# librealsense SDK pin lives in the global LIBREALSENSE_VERSION ARG at the top
# (the `rs_sdk` FROM must reference it pre-FROM).
ARG REALSENSE_ROS_VERSION="4.58.2"

# COPY the prebuilt SDK trees in BEFORE the wrapper build (issue #97).
# librealsense is now consumed as a PREBUILT GHCR image (the `rs_sdk` stage at
# the top), not compiled here -- CI no longer pays the ~15-25 min librealsense
# compile per run, only the colcon wrapper build. The full SDK (viewer + rs-* +
# gl) overlays the devel ROS prefix (mirrors the apt layout: entrypoint/paths
# unchanged, find_package(realsense2) resolves it); the tools-pruned copy stages
# at /opt/rs-stage for the runtime overlay. The SDK was built with
# FORCE_RSUSB_BACKEND=true (userspace, no kernel module -- the whole point for
# the Pi) and no Python bindings (see docker/librealsense/Dockerfile).
COPY --from=rs_sdk /rs-full/opt/ros/${ROS_DISTRO} /opt/ros/${ROS_DISTRO}
COPY --from=rs_sdk /rs-stage/opt/ros/${ROS_DISTRO} /opt/rs-stage/opt/ros/${ROS_DISTRO}

# ldconfig registers the copied librealsense .so, then realsense-ros (wrapper)
# is built with colcon against the prebuilt SDK and installed into
# /opt/ros/${ROS_DISTRO}, mirroring what the apt packages did (verified via
# `dpkg -L`), so the base setup.bash discovers them through the ament index and
# entrypoint/bashrc/smoke paths stay unchanged. LIVE install feeds the devel
# image (viewer + rs-* tools); a parallel DESTDIR=/opt/rs-stage per-package
# `cmake --install` stages an omission-proof copy tree for runtime's
# COPY --from=devel. We deliberately do NOT use colcon's prefix-level
# setup.bash (it would clobber the base image's /opt/ros/<distro>/setup.bash);
# per-package `cmake --install` still captures the ament markers
# (share/ament_index/resource_index/packages/realsense2_*). The wrapper's
# package.xml files are preserved under /opt/rs-stage-src for runtime's online
# exec-dep resolution. FORCE_RSUSB_BACKEND => userspace, so NO kernel patching.
# `. "${prefix}/setup.bash"` below sources a ROS-generated file that hadolint's
# shellcheck cannot follow; ROS setup.bash is not a repo file (SC1091).
# hadolint ignore=SC1091
RUN prefix="/opt/ros/${ROS_DISTRO}" && \
    stage="/opt/rs-stage" && \
    ldconfig && \
    mkdir -p /tmp/rs_ws/src && \
    git clone --depth 1 --branch "${REALSENSE_ROS_VERSION}" \
        https://github.com/IntelRealSense/realsense-ros.git /tmp/rs_ws/src/realsense-ros && \
    apt-get update && \
    (rosdep init 2>/dev/null || true) && \
    rosdep update && \
    rosdep install -i --from-path /tmp/rs_ws/src --rosdistro "${ROS_DISTRO}" \
        --skip-keys=librealsense2 -y && \
    set +u && . "${prefix}/setup.bash" && set -u && \
    colcon build --base-paths /tmp/rs_ws/src --build-base /tmp/rs_ws/build \
        --install-base /tmp/rs_ws/install \
        --cmake-args \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_WITH_DDS=OFF && \
    for b in /tmp/rs_ws/build/*/; do \
        cmake --install "${b}" --prefix "${prefix}" && \
        DESTDIR="${stage}" cmake --install "${b}" --prefix "${prefix}"; \
    done && \
    cp -r /tmp/rs_ws/src /opt/rs-stage-src && \
    rm -rf /tmp/rs_ws /var/lib/apt/lists/*

COPY --chmod=0755 "./${ENTRYPOINT_FILE}" "/entrypoint.sh"
COPY --chown="${USER}":"${GROUP}" --chmod=0755 .base/config "${CONFIG_DIR}"
COPY --chown="${USER}":"${GROUP}" --chmod=0755 "${CONFIG_SRC}" "${CONFIG_DIR}"

# Copy RealSense udev rules
RUN mkdir -p /etc/udev/rules.d
COPY --chmod=0644 config/realsense/99-realsense-libusb.rules /etc/udev/rules.d/

USER "${USER}"


# Setup shell, terminator, tmux
RUN cat "${CONFIG_DIR}"/shell/bashrc >> "${HOME}/.bashrc" && \
    chown "${USER}":"${GROUP}" "${HOME}/.bashrc" && \
    mkdir -p "${HOME}/.bashrc.d" && \
    cp -n "${CONFIG_DIR}"/shell/bashrc.d/*.sh "${HOME}/.bashrc.d/" 2>/dev/null || true && \
    chown -R "${USER}":"${GROUP}" "${HOME}/.bashrc.d" && \
    "${CONFIG_DIR}"/shell/terminator/setup.sh && \
    "${CONFIG_DIR}"/shell/tmux/setup.sh && \
    sudo rm -rf "${CONFIG_DIR}" "${SETUP_DIR}"

WORKDIR "${HOME}/work"

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]

############################## devel-test (ephemeral) ##############################
# Resolves to test-tools:local (local just build) or
# ghcr.io/ycpss91255-docker/test-tools:vX.Y.Z (CI); see TEST_TOOLS_IMAGE at top.
# hadolint ignore=DL3006
FROM ${TEST_TOOLS_IMAGE} AS test-tools-stage

FROM devel AS devel-test

USER root

# Install lint tools (from the pre-built multi-arch test-tools image)
COPY --from=test-tools-stage /usr/local/bin/shellcheck /usr/local/bin/shellcheck
COPY --from=test-tools-stage /usr/local/bin/hadolint /usr/local/bin/hadolint

# Lint: ShellCheck (.sh) + Hadolint (Dockerfile)
COPY .hadolint.yaml /lint/.hadolint.yaml
COPY Dockerfile /lint/Dockerfile
# base v0.41.0 moved the wrapper scripts under .base/script/docker/wrapper/,
# so the old `COPY .base/script/docker/*.sh` glob matched nothing and broke
# this stage. The repo's own script/*.sh are symlinks to those wrappers, so
# `COPY script/*.sh /lint/` already dereferences and lints them.
COPY script/*.sh /lint/
COPY .base/script/docker/lib /lint/lib
RUN shellcheck -S warning /lint/*.sh /lint/lib/*.sh
WORKDIR /lint
RUN hadolint Dockerfile

# Install bats (the bats-support/assert/mock extensions are already merged
# into /usr/lib/bats inside the test-tools image)
COPY --from=test-tools-stage /opt/bats /opt/bats
COPY --from=test-tools-stage /usr/lib/bats /usr/lib/bats
RUN ln -sf /opt/bats/bin/bats /usr/local/bin/bats

ENV BATS_LIB_PATH="/usr/lib/bats"

# Smoke test
COPY .base/test/smoke/ /smoke_test/
COPY test/smoke/ /smoke_test/

ARG USER_NAME="user"
ARG USER="${USER_NAME}"
# Surface the configured user so the smoke test can assert the image was
# actually built as it (regression guard for the USER_NAME build contract).
# Ephemeral devel-test stage only -- not shipped in devel/runtime.
ENV CONTAINER_EXPECTED_USER="${USER_NAME}"
USER "${USER}"

RUN bats /smoke_test/

############################## runtime-base ##############################
FROM sys AS runtime-base

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        sudo \
        tini \
        # rosdep resolves runtime's exec ROS deps online against the wrapper
        # package.xml copied from devel (#97).
        python3-rosdep \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

############################## runtime ##############################
FROM runtime-base AS runtime

ARG ROS_DISTRO
ARG USER_NAME="user"
ARG USER="${USER_NAME}"

# RealSense libs + wrapper, staged from the devel source build (#97). Copy only
# the SDK/wrapper libs (lib/) and the ament-indexed resources (share/); the
# bin/ SDK tools (realsense-viewer, rs-*) are deliberately omitted from runtime.
# Install into /opt/ros/${ROS_DISTRO} exactly where apt put them, so the base
# setup.bash discovers the packages via the ament index -- entrypoint/bashrc/
# smoke paths unchanged. /tmp/rs-src holds ONLY the wrapper package.xml (not the
# whole ros share tree) so runtime's rosdep scans just those manifests.
COPY --from=devel /opt/rs-stage/opt/ros/${ROS_DISTRO}/lib/   /opt/ros/${ROS_DISTRO}/lib/
COPY --from=devel /opt/rs-stage/opt/ros/${ROS_DISTRO}/share/ /opt/ros/${ROS_DISTRO}/share/
COPY --from=devel /opt/rs-stage-src                          /tmp/rs-src

# Resolve the wrapper's exec ROS deps online (image_transport,
# diagnostic_updater, ...) -- they are missing from ros-base once the apt
# realsense meta is gone. --dependency-types=exec (runtime needs only exec
# deps) and --skip-keys=librealsense2 (do NOT let rosdep apt-install the SDK we
# built from source; SONAME librealsense2.so.2.58 would collide). Also append a
# ROS source to /etc/bash.bashrc so interactive `docker exec` shells get `ros2`
# on PATH: the entrypoint sources ROS for PID 1 only and `docker exec` bypasses
# it. /etc/bash.bashrc is read by interactive shells only (its leading
# non-interactive guard short-circuits otherwise), so non-interactive
# correctness is untouched. devel already does this via its bashrc.d drop-in
# (base#657, #87). Folded into one RUN to avoid a consecutive-RUN lint (DL3059).
RUN rm -f /opt/ros/"${ROS_DISTRO}"/lib/librealsense2-gl* && \
    apt-get update && \
    (rosdep init 2>/dev/null || true) && \
    rosdep update && \
    rosdep install -i --from-path /tmp/rs-src --rosdistro "${ROS_DISTRO}" \
        --dependency-types=exec --skip-keys=librealsense2 -y && \
    rm -rf /tmp/rs-src && \
    ldconfig && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    printf 'source /opt/ros/%s/setup.bash\n' "${ROS_DISTRO}" >> /etc/bash.bashrc

# Copy RealSense udev rules
RUN mkdir -p /etc/udev/rules.d
COPY --chmod=0644 config/realsense/99-realsense-libusb.rules /etc/udev/rules.d/

COPY --chmod=0755 script/entrypoint.sh /entrypoint.sh

USER "${USER}"
WORKDIR "${HOME}/work"

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
# initial_reset:=true resets the camera at startup so a D455 cold-start on the
# RSUSB/arm64 backend does not wedge the first stream-open (RS2_USB_STATUS_IO,
# topics stuck at 0 Hz). Adds a few seconds; override the arg to skip.
CMD ["ros2", "launch", "realsense2_camera", "rs_align_depth_launch.py", "initial_reset:=true"]

############################## runtime-test (ephemeral) ##############################
# Install-check smoke for the runtime image (template v0.21.1+ #243).
#
# This repo overrides the default smoke (USER + bash) to verify that the
# realsense2_camera node's shared libraries all resolve in the runtime
# image -- the exact regression class that went undetected in
# ros1_bridge#123 (a missing transitive .so the devel-stage bats never
# exercised, because devel carries the full build deps). ldd every
# installed file under the package lib dir and fail on any "not found";
# the non-empty guard prevents a vacuous pass if the dir is ever
# missing/empty.
#
# `bash -c` (not `sh -c`): the command sources ROS setup.bash and uses a
# bash for-loop. The inner bash runs without the outer SHELL's
# -euo pipefail, so `source` under nounset is safe (matches ros1_bridge).
FROM runtime AS runtime-test

ARG RUNTIME_SMOKE_CMD='whoami && bash --version && \
  source /opt/ros/${ROS_DISTRO}/setup.bash && \
  ros2 pkg prefix realsense2_camera >/dev/null || { echo "RUNTIME SMOKE FAIL: realsense2_camera ament marker missing"; exit 1; } && \
  rs_dir="/opt/ros/${ROS_DISTRO}/lib/realsense2_camera" && \
  test -d "${rs_dir}" && \
  bins="$(find "${rs_dir}" -maxdepth 1 \( -type f -o -type l \))" && \
  test -n "${bins}" && \
  for f in ${bins}; do \
    echo "--- ldd: ${f} ---"; ldd "${f}" || true; \
    if ldd "${f}" 2>&1 | grep -q "not found"; then \
      echo "RUNTIME SMOKE FAIL: unresolved shared library in ${f}"; exit 1; \
    fi; \
  done && \
  echo "RUNTIME SMOKE OK: realsense2_camera shared libraries resolved"'
RUN bash -c "${RUNTIME_SMOKE_CMD}"
