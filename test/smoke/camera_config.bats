#!/usr/bin/env bats
#
# Camera-config wiring smoke (modeled on app/ros1_bridge's /bridge.yaml).
#
# The root `camera.yaml` symlink selects the active RealSense config; the
# Dockerfile COPYs its target to /camera_config.yaml and the entrypoint launches
# the camera with it only when that file is non-empty. The default symlink
# target is config/realsense/custom/none.yaml (empty), so the stock upstream
# default runs. These guards pin that wiring: /camera_config.yaml must exist
# (proving the symlink resolved at build time and Docker COPY followed it), be
# empty by default, and the entrypoint must carry the `[ -s ]` conditional +
# config_file launch. The whole Dockerfile is at /lint/Dockerfile (devel-test).

setup() {
    load "${BATS_TEST_DIRNAME}/test_helper"
    DOCKERFILE="/lint/Dockerfile"
    ENTRYPOINT="/entrypoint.sh"
    CAMERA_CONFIG="/camera_config.yaml"
}

@test "camera.yaml symlink resolved into the image (/camera_config.yaml exists)" {
    # Docker COPY follows the root camera.yaml symlink and copies its TARGET
    # content; the file must be present in the built image.
    assert_file_exists "${CAMERA_CONFIG}"
}

@test "default camera config is empty (stock upstream default)" {
    # Default symlink target is config/realsense/custom/none.yaml (0 bytes), so
    # the entrypoint's [ -s ] guard is false and the stock default launch runs.
    assert_file_exists "${CAMERA_CONFIG}"
    run test -s "${CAMERA_CONFIG}"
    assert_failure
}

@test "entrypoint gates the camera launch on a non-empty config ([ -s ])" {
    assert_file_exists "${ENTRYPOINT}"
    run grep -F -- '-s "${_camera_config}"' "${ENTRYPOINT}"
    assert_success
}

@test "entrypoint launches rs_launch.py with config_file when a config is active" {
    assert_file_exists "${ENTRYPOINT}"
    run grep -F -- 'config_file:="${_camera_config}"' "${ENTRYPOINT}"
    assert_success
    run grep -F -- 'initial_reset:=true' "${ENTRYPOINT}"
    assert_success
}

@test "Dockerfile declares CAMERA_CONFIG and COPYs it to /camera_config.yaml" {
    assert_file_exists "${DOCKERFILE}"
    run grep -F 'ARG CAMERA_CONFIG="camera.yaml"' "${DOCKERFILE}"
    assert_success
    run grep -F 'COPY --chmod=0644 "${CAMERA_CONFIG}" /camera_config.yaml' "${DOCKERFILE}"
    assert_success
}
