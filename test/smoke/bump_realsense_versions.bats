#!/usr/bin/env bats

setup() {
    load "${BATS_TEST_DIRNAME}/test_helper"
}

# -------------------- bump_realsense_versions.sh --------------------
# Rewrites the pinned LIBREALSENSE_VERSION / REALSENSE_ROS_VERSION Dockerfile
# ARGs when a newer upstream release exists. The GitHub queries need network +
# gh auth, so here we assert the --help contract plus the pure ARG parser /
# rewriter (current_arg / set_arg) against a fixture Dockerfile. main is guarded
# to direct execution, so sourcing the script only defines the helpers.

@test "bump_realsense_versions.sh -h exits 0" {
    run bash /lint/bump_realsense_versions.sh -h
    assert_success
}

@test "bump_realsense_versions.sh --help exits 0" {
    run bash /lint/bump_realsense_versions.sh --help
    assert_success
}

@test "bump_realsense_versions.sh -h prints usage" {
    run bash /lint/bump_realsense_versions.sh -h
    assert_line --partial "Usage:"
}

@test "bump_realsense_versions.sh is executable" {
    [ -x /lint/bump_realsense_versions.sh ]
}

@test "current_arg returns the pinned value from the Dockerfile ARG" {
    run bash -c '
        f="$(mktemp)"
        printf "ARG LIBREALSENSE_VERSION=\"v2.58.2\"\n" > "$f"
        DOCKERFILE="$f"
        source /lint/bump_realsense_versions.sh
        current_arg LIBREALSENSE_VERSION
        rm -f "$f"'
    assert_success
    assert_output "v2.58.2"
}

@test "set_arg rewrites only the target ARG line (round-trip; others untouched)" {
    run bash -c '
        f="$(mktemp)"
        printf "ARG LIBREALSENSE_VERSION=\"v2.58.2\"\nARG REALSENSE_ROS_VERSION=\"4.58.2\"\n" > "$f"
        DOCKERFILE="$f"
        source /lint/bump_realsense_versions.sh
        set_arg LIBREALSENSE_VERSION v9.9.9
        echo "lib=$(current_arg LIBREALSENSE_VERSION)"
        echo "ros=$(current_arg REALSENSE_ROS_VERSION)"
        rm -f "$f"'
    assert_success
    assert_line "lib=v9.9.9"
    assert_line "ros=4.58.2"
}
