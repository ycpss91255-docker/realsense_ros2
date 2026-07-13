#!/usr/bin/env bats
#
# Camera-config wiring smoke (modeled on app/ros1_bridge's /bridge.yaml).
#
# The root `camera.yaml` symlink selects the active RealSense config; the
# Dockerfile COPYs its target to /camera_config.yaml and the entrypoint launches
# the camera with it only when that file is non-empty AND the command is
# `ros2 launch`. The default symlink target is config/realsense/yaml/custom/none.yaml
# (empty), so the stock upstream default runs. entrypoint.sh factors the gate
# into the pure `_apply_camera_config`, which resolves the final argv into
# CONFIGURED_ARGV without executing; the ROS source + exec are guarded to the
# real invocation, so these tests can source it safely.

setup() {
    load "${BATS_TEST_DIRNAME}/test_helper"
}

@test "camera.yaml symlink resolved into the image (/camera_config.yaml exists)" {
    # Docker COPY follows the root camera.yaml symlink and copies its TARGET
    # content; the file must be present in the built image.
    assert_file_exists "/camera_config.yaml"
}

@test "default baked camera config is empty (stock upstream default)" {
    # none.yaml is a 0-byte marker: [ -s ] is false, so the entrypoint keeps the
    # stock CMD -> the camera streams the upstream defaults (640x480x30).
    assert_file_exists "/camera_config.yaml"
    run test -s "/camera_config.yaml"
    assert_failure
}

@test "entrypoint leaves the stock launch unchanged for an empty config" {
    # Empty /camera_config.yaml (the default): [ -s ] is false, argv untouched.
    run bash -c '
        source /entrypoint.sh
        _apply_camera_config ros2 launch realsense2_camera rs_align_depth_launch.py initial_reset:=true
        echo "${CONFIGURED_ARGV[@]}"'
    assert_success
    assert_output "ros2 launch realsense2_camera rs_align_depth_launch.py initial_reset:=true"
}

@test "entrypoint applies config_file:= for a non-empty camera config" {
    run bash -c '
        f="$(mktemp)"; printf "color_width: 640\n" > "$f"
        source /entrypoint.sh
        CAMERA_CONFIG_FILE="$f"
        _apply_camera_config ros2 launch realsense2_camera rs_launch.py
        echo "${CONFIGURED_ARGV[@]}"
        rm -f "$f"'
    assert_success
    assert_output --partial "config_file:=/tmp/"
    assert_output --partial "initial_reset:=true"
}

@test "entrypoint does not hijack a non-launch command even with a config" {
    # The devel image ships CMD bash; a baked profile must not turn it into a
    # camera launch.
    run bash -c '
        f="$(mktemp)"; printf "color_width: 640\n" > "$f"
        source /entrypoint.sh
        CAMERA_CONFIG_FILE="$f"
        _apply_camera_config bash
        rm -f "$f"
        echo "${CONFIGURED_ARGV[@]}"'
    assert_success
    assert_output "bash"
}

@test "entrypoint does not hijack ros2 run (only ros2 launch) even with a config" {
    # Only `ros2 launch` is gated; `ros2 run <pkg> <exe>` passes through so the
    # config swap never clobbers a non-launch subcommand.
    run bash -c '
        f="$(mktemp)"; printf "color_width: 640\n" > "$f"
        source /entrypoint.sh
        CAMERA_CONFIG_FILE="$f"
        _apply_camera_config ros2 run realsense2_camera realsense2_camera_node
        rm -f "$f"
        echo "${CONFIGURED_ARGV[@]}"'
    assert_success
    assert_output "ros2 run realsense2_camera realsense2_camera_node"
}
