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

# -------------------- RealSense packages --------------------

@test "realsense2_camera is installed" {
    run dpkg -l ros-${ROS_DISTRO}-realsense2-camera
    assert_success
}

@test "realsense2_description is installed" {
    run dpkg -l ros-${ROS_DISTRO}-realsense2-description
    assert_success
}

@test "RealSense SDK tools load their shared libraries (rs-enumerate-devices)" {
    # ros-${ROS_DISTRO}-librealsense2 (a dependency of realsense2-camera) ships
    # the SDK CLI tools (rs-enumerate-devices, realsense-viewer, rs-*) under
    # /opt/ros/${ROS_DISTRO}/bin. They need ROS sourced for PATH +
    # LD_LIBRARY_PATH. With no camera attached the tool reports "No device
    # detected" and exits 0; a missing tool or unresolvable shared library
    # fails (exit 127, "error while loading shared libraries"). This guards
    # that the tools are actually usable, not just present on disk.
    run bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash && rs-enumerate-devices"
    refute_output --partial "error while loading shared libraries"
    assert_success
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
