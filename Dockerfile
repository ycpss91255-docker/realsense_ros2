ARG ROS_DISTRO="humble"
ARG ROS_TAG="ros-base"
ARG UBUNTU_CODENAME="jammy"
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
        # RealSense packages
        ros-${ROS_DISTRO}-realsense2-camera \
        ros-${ROS_DISTRO}-realsense2-description \
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

ARG USER_NAME="user"
ARG USER_GROUP="user"
ARG USER="${USER_NAME}"
ARG GROUP="${USER_GROUP}"
ARG ENTRYPOINT_FILE="script/entrypoint.sh"
ARG CONFIG_DIR="/tmp/config"
ARG SETUP_DIR="/tmp/setup"
ARG CONFIG_SRC="config"

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
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

############################## runtime ##############################
FROM runtime-base AS runtime

ARG ROS_DISTRO
ARG USER_NAME="user"
ARG USER="${USER_NAME}"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ros-${ROS_DISTRO}-realsense2-camera \
        ros-${ROS_DISTRO}-realsense2-description \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy RealSense udev rules
RUN mkdir -p /etc/udev/rules.d
COPY --chmod=0644 config/realsense/99-realsense-libusb.rules /etc/udev/rules.d/

COPY --chmod=0755 script/entrypoint.sh /entrypoint.sh

USER "${USER}"
WORKDIR "${HOME}/work"

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
CMD ["ros2", "launch", "realsense2_camera", "rs_launch.py"]

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
