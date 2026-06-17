ARG ROS_DISTRO="humble"
ARG ROS_TAG="ros-base"
ARG UBUNTU_CODENAME="jammy"

############################## devel-test tool sources ##############################
FROM bats/bats:1.11.0 AS bats-src

FROM alpine:3.21 AS bats-extensions
RUN apk add --no-cache git && \
    git clone --depth 1 -b v0.3.0 \
        https://github.com/bats-core/bats-support /bats/bats-support && \
    git clone --depth 1 -b v2.1.0 \
        https://github.com/bats-core/bats-assert  /bats/bats-assert

FROM alpine:3.21 AS lint-tools
SHELL ["/bin/ash", "-o", "pipefail", "-c"]
RUN apk add --no-cache curl xz && \
    curl -fsSL \
        https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz \
        | tar -xJ -C /tmp && \
    mv /tmp/shellcheck-v0.10.0/shellcheck /usr/local/bin/shellcheck && \
    curl -fsSL -o /usr/local/bin/hadolint \
        https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64 && \
    chmod +x /usr/local/bin/hadolint

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

# Intel RealSense D400 Series Dynamic Calibration Tool (librscalibrationtool).
# Not in the ROS apt repo, so pull it from Intel's librealsense apt repo. The
# package is amd64-only and self-contained (no Depends on Intel's librealsense2),
# so it does not clash with the ROS-provided librealsense. Non-amd64 (e.g. ARM64)
# is skipped -- Intel ships no build there -- so the multi-arch image still builds.
# The deb declares no Depends, so its runtime libs are added explicitly
# (freeglut3 -> libglut.so.3). The repo is signed by key FB0B24895113F120; Intel's
# published librealsense.pgp still carries only the old C8B3A55A6F3EFCDE key, so
# fetch the current key from the Ubuntu keyserver (apt on jammy accepts an armored
# signed-by keyring, so no gnupg is needed at build time).
ARG RS_APT_KEY="FB0B24895113F120"
RUN arch="$(dpkg --print-architecture)" && \
    if [ "${arch}" = "amd64" ]; then \
        install -m 0755 -d /etc/apt/keyrings && \
        curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${RS_APT_KEY}" \
            -o /etc/apt/keyrings/librealsense.asc && \
        echo "deb [signed-by=/etc/apt/keyrings/librealsense.asc] https://librealsense.intel.com/Debian/apt-repo ${UBUNTU_CODENAME} main" \
            > /etc/apt/sources.list.d/librealsense.list && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            librscalibrationtool \
            freeglut3 && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo "Skipping librscalibrationtool: not available for ${arch}"; \
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
FROM devel AS devel-test

USER root

# Install lint tools
COPY --from=lint-tools /usr/local/bin/shellcheck /usr/local/bin/shellcheck
COPY --from=lint-tools /usr/local/bin/hadolint /usr/local/bin/hadolint

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

# Install bats
COPY --from=bats-src /opt/bats /opt/bats
COPY --from=bats-src /usr/lib/bats /usr/lib/bats
COPY --from=bats-extensions /bats /usr/lib/bats
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
