#!/usr/bin/env bats

setup() {
    load "${BATS_TEST_DIRNAME}/test_helper"
}

# -------------------- ROS environment --------------------

@test "ROS_DISTRO is set" {
    assert [ -n "${ROS_DISTRO}" ]
}

@test "ROS 2 setup.bash exists" {
    assert [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]
}

@test "ROS 2 setup.bash can be sourced" {
    run bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash"
    assert_success
}

@test "interactive shells source ROS (ros2 on PATH via bashrc.d)" {
    # The base bashrc is ROS-agnostic and loads ~/.bashrc.d/*.sh for interactive
    # shells; this repo ships config/shell/bashrc.d/10-ros-source.sh to source
    # ROS. Without it, ros2 / realsense-viewer / rviz2 are "command not found"
    # in interactive just run / just exec shells even though they are installed.
    assert [ -f "${HOME}/.bashrc.d/10-ros-source.sh" ]
    run bash -c "source ${HOME}/.bashrc.d/10-ros-source.sh && command -v ros2"
    assert_success
    assert_output --partial "/opt/ros/${ROS_DISTRO}/bin/ros2"
}

# -------------------- RealSense packages --------------------

@test "realsense2_camera is discoverable via ament index (source build)" {
    # #97: realsense2_camera is built from source (not apt), installed into
    # /opt/ros/${ROS_DISTRO} via per-package `cmake --install`. Assert the
    # ament index marker is present -- this is the exact class the runtime
    # DESTDIR staging + COPY must preserve for `ros2 pkg prefix` to work.
    assert [ -f "/opt/ros/${ROS_DISTRO}/share/ament_index/resource_index/packages/realsense2_camera" ]
}

@test "realsense2_description is discoverable via ament index (source build)" {
    # #97: realsense2_description is bundled in the realsense-ros repo, so the
    # source build covers it too. Same ament-marker check.
    assert [ -f "/opt/ros/${ROS_DISTRO}/share/ament_index/resource_index/packages/realsense2_description" ]
}

@test "RealSense SDK tool libraries resolve (rs-enumerate-devices)" {
    # The librealsense SDK is now a ROS-agnostic image installed into /usr/local,
    # so its CLI tools (rs-enumerate-devices, realsense-viewer, rs-*) ship under
    # /usr/local/bin and their .so deps resolve via ldconfig (/usr/local/lib) --
    # no ROS sourcing needed for LD_LIBRARY_PATH. ldd the binary to prove its
    # shared libraries (librealsense2.so.*, ...) all resolve -- camera-independent,
    # so it behaves the same in CI (no device) and on a dev box. A packaging /
    # lib-path regression surfaces as an unresolved "not found". (Running the
    # tool itself is avoided: with no camera it exits non-zero, which is not a
    # load failure.)
    run bash -c "ldd /usr/local/bin/rs-enumerate-devices"
    assert_success
    refute_output --partial "not found"
}

# -------------------- Desktop GUI (devel) --------------------

@test "ROS 2 desktop is installed (rviz2 on PATH)" {
    # devel-base installs ros-${ROS_DISTRO}-desktop so GUI tools (rviz2,
    # realsense-viewer) are available; the runtime image stays on ros-base.
    run bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash && command -v rviz2"
    assert_success
    assert_output --partial "/opt/ros/${ROS_DISTRO}/bin/rviz2"
}

@test "Qt xcb platform plugin is present (realsense-viewer / rviz2 GUI)" {
    # GUI Qt apps dlopen the xcb platform plugin at startup; ros-base lacks it,
    # ros-${ROS_DISTRO}-desktop provides it. Its absence is why realsense-viewer
    # fails to open a window even when its direct ldd deps resolve.
    assert [ -n "$(find /usr/lib -name libqxcb.so 2>/dev/null | head -1)" ]
}

# -------------------- Base tools --------------------

@test "git is available" {
    run git --version
    assert_success
}

@test "vim is available" {
    run vim --version
    assert_success
}

@test "sudo is available" {
    run sudo --version
    assert_success
}

@test "sudo passwordless works" {
    run sudo true
    assert_success
}

# -------------------- System --------------------

@test "User is not root" {
    assert [ "$(id -u)" -ne 0 ]
}

@test "HOME is set and exists" {
    assert [ -n "${HOME}" ]
    assert [ -d "${HOME}" ]
}

@test "container user matches the configured USER_NAME (base v0.41.0 build contract)" {
    # Regression guard: the Dockerfile must consume the USER_NAME / USER_UID /
    # USER_GROUP / USER_GID build-args that base v0.41.0's compose + CI inject.
    # If it falls back to the legacy default user, the container HOME diverges
    # from compose's /home/${USER_NAME}/work mount and `just run` breaks.
    assert [ -n "${CONTAINER_EXPECTED_USER}" ]
    assert_equal "$(id -un)" "${CONTAINER_EXPECTED_USER}"
}

@test "HOME path matches the container user" {
    assert_equal "${HOME}" "/home/$(id -un)"
}

@test "Timezone is Asia/Taipei" {
    run cat /etc/timezone
    assert_output "Asia/Taipei"
}

@test "LANG is en_US.UTF-8" {
    assert_equal "${LANG}" "en_US.UTF-8"
}

@test "LC_ALL is en_US.UTF-8" {
    assert_equal "${LC_ALL}" "en_US.UTF-8"
}

@test "entrypoint.sh exists and executable" {
    assert [ -x "/entrypoint.sh" ]
}

@test "RealSense udev rules exist" {
    assert [ -f "/etc/udev/rules.d/99-realsense-libusb.rules" ]
}

@test "Work directory exists" {
    assert [ -d "${HOME}/work" ]
}
