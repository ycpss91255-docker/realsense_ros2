#!/usr/bin/env bats
#
# Runtime install-check smoke, run by the runtime-test stage INSIDE the real,
# minimal runtime image (base#647). devel-stage bats cannot catch these: devel
# carries the full build deps, so a missing transitive .so only surfaces in the
# stripped-down runtime (the ros1_bridge#123 regression class).
#
# Kept in test/smoke/runtime/ -- a dedicated dir -- so devel-test's
# non-recursive `bats /smoke_test/` never runs these against the wrong image.

setup() {
    load "${BATS_TEST_DIRNAME}/test_helper"
    # ROS_DISTRO is baked into the runtime-test stage as CONTAINER_ROS_DISTRO.
    ROS_DISTRO="${CONTAINER_ROS_DISTRO:-${ROS_DISTRO:-}}"
    RS_LIB_DIR="/opt/ros/${ROS_DISTRO}/lib/realsense2_camera"
    # Source ROS so the linker sees the same LD_LIBRARY_PATH the launched node
    # would. set +u: ROS setup scripts reference unbound vars; do not re-enable
    # nounset afterwards (it would leak into the test body).
    set +u
    # shellcheck disable=SC1090
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
}

@test "realsense2_camera lib dir exists and is non-empty" {
    assert [ -d "${RS_LIB_DIR}" ]
    # Non-empty guard: a missing/empty dir must not vacuously pass the ldd test.
    run find "${RS_LIB_DIR}" -maxdepth 1 \( -type f -o -type l \)
    assert_success
    assert [ -n "${output}" ]
}

@test "all realsense2_camera shared objects resolve (ldd, no 'not found')" {
    # -type l as well as -type f: a lib shipped as a symlink to a versioned .so
    # must be ldd-checked too (#71).
    local f missing=""
    while IFS= read -r f; do
        if ldd "${f}" 2>&1 | grep -q "not found"; then
            missing+="${f} "
        fi
    done < <(find "${RS_LIB_DIR}" -maxdepth 1 \( -type f -o -type l \))
    if [ -n "${missing}" ]; then
        echo "unresolved shared libraries in: ${missing}"
        return 1
    fi
}

@test "ros2 CLI resolves the realsense2_camera package" {
    # The runtime CMD is `ros2 launch realsense2_camera rs_launch.py`, so both
    # the ros2 CLI and the package must be present in the minimal runtime.
    run ros2 pkg prefix realsense2_camera
    assert_success
}

@test "entrypoint.sh exists and is executable" {
    assert [ -x /entrypoint.sh ]
}

@test "runtime runs as the configured non-root user" {
    assert_equal "$(id -un)" "${CONTAINER_EXPECTED_USER}"
    assert [ "$(id -u)" -ne 0 ]
}
