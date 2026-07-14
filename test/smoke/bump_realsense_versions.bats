#!/usr/bin/env bats

setup() {
    load "${BATS_TEST_DIRNAME}/test_helper"
}

# -------------------- bump_realsense_versions.sh --------------------
# Rewrites the pinned LIBREALSENSE_VERSION / REALSENSE_ROS_VERSION Dockerfile
# ARGs when a newer upstream release exists, with realsense-ros driving the pair.
# The GitHub queries need network + gh auth, so here we assert the --help
# contract plus the pure helpers (ARG parse/rewrite, the find_package minor
# parser, the same-minor tag picker, the realsense-ros classification, and the
# changelog inserter) against fixtures. main is guarded to direct execution, so
# sourcing the script only defines the helpers -- no network.

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

@test "required_librealsense_minor parses find_package(realsense2 2.58.0) -> 2.58" {
    run bash -c '
        source /lint/bump_realsense_versions.sh
        required_librealsense_minor "cmake_minimum_required(VERSION 3.5)
find_package(realsense2 2.58.0 REQUIRED)"'
    assert_success
    assert_output "2.58"
}

@test "required_librealsense_version parses the declared floor 2.58.0" {
    run bash -c '
        source /lint/bump_realsense_versions.sh
        required_librealsense_version "find_package(realsense2 2.58.0)"'
    assert_success
    assert_output "2.58.0"
}

@test "latest_tag_in_minor picks the highest v2.58.z (ignores other minors)" {
    run bash -c '
        source /lint/bump_realsense_versions.sh
        latest_tag_in_minor "v2.57.9
v2.58.0
v2.58.2
v2.59.0" 2.58'
    assert_success
    assert_output "v2.58.2"
}

@test "same_minor_bump: a realsense-ros patch (same minor) is safe (exit 0)" {
    # 4.58.1 -> 4.58.2 keeps the declared realsense2 minor, so it is a drop-in.
    run bash -c '
        source /lint/bump_realsense_versions.sh
        same_minor_bump 4.58.1 4.58.2'
    assert_success
}

@test "same_minor_bump: a realsense-ros minor change is not safe (exit 1)" {
    run bash -c '
        source /lint/bump_realsense_versions.sh
        same_minor_bump 4.58.2 4.59.0'
    assert_failure
}

@test "same_minor_bump: a realsense-ros major change is not safe (exit 1)" {
    run bash -c '
        source /lint/bump_realsense_versions.sh
        same_minor_bump 4.58.2 5.0.0'
    assert_failure
}

@test "prepend_changelog_entry inserts under the existing ### Changed subheading" {
    run bash -c '
        f="$(mktemp)"
        printf "# Changelog\n\n## [Unreleased]\n\n### Changed\n- old entry\n" > "$f"
        CHANGELOG="$f"
        source /lint/bump_realsense_versions.sh
        prepend_changelog_entry "Bumped pinned RealSense sources"
        cat "$f"
        rm -f "$f"'
    assert_success
    assert_line "### Changed"
    assert_line "- Bumped pinned RealSense sources"
    assert_line "- old entry"
}

@test "prepend_changelog_entry creates ### Changed when the Unreleased section lacks one" {
    run bash -c '
        f="$(mktemp)"
        printf "# Changelog\n\n## [Unreleased]\n\n### Fixed\n- kept\n\n## [1.0.0]\n- old\n" > "$f"
        CHANGELOG="$f"
        source /lint/bump_realsense_versions.sh
        prepend_changelog_entry "Bumped pinned RealSense sources"
        cat "$f"
        rm -f "$f"'
    assert_success
    assert_line "### Changed"
    assert_line "- Bumped pinned RealSense sources"
    assert_line "- kept"
}
