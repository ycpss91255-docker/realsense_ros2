#!/usr/bin/env bats
#
# Static Dockerfile guards (regression for #71).
#
# Both defects are latent under the default build params (USER == GROUP, and
# the realsense2_camera lib dir ships no symlinks today), so neither has a
# runtime surface that a behavioural smoke could exercise. These guards pin the
# corrected source lines instead: they fail on the pre-#71 Dockerfile and pass
# on the fixed one. The whole Dockerfile is copied to /lint/Dockerfile in the
# devel-test stage (for hadolint), so it is available to read here.

setup() {
    load "${BATS_TEST_DIRNAME}/test_helper"
    DOCKERFILE="/lint/Dockerfile"
}

@test "groupadd new-group branch names the group after \${GROUP}, not \${USER} (#71)" {
    # Dockerfile:59 -- the else branch must create the group named after
    # USER_GROUP. Using \${USER} silently works only while USER == GROUP and
    # becomes a real bug the moment they differ.
    assert_file_exists "${DOCKERFILE}"
    run grep -E 'groupadd -g "\$\{GID\}"' "${DOCKERFILE}"
    assert_success
    assert_output --partial 'groupadd -g "${GID}" "${GROUP}"'
    refute_output --partial 'groupadd -g "${GID}" "${USER}"'
}

@test "runtime-test ldd smoke covers symlinks, not just regular files (#71)" {
    # Dockerfile:runtime-test -- the find must include -type l so a packaged
    # tool/lib that ships as a symlink to a versioned .so is still ldd-checked.
    assert_file_exists "${DOCKERFILE}"
    run grep -E 'find "\$\{rs_dir\}" -maxdepth 1' "${DOCKERFILE}"
    assert_success
    assert_output --partial '-type l'
}

@test "devel-base/runtime no longer apt-install the RealSense packages (#97)" {
    # #97 migrates realsense2-camera / -description from apt to a pinned source
    # build; the apt install lines must be gone from every stage or the image
    # would carry a duplicate/stale SDK on top of the source build.
    assert_file_exists "${DOCKERFILE}"
    run grep -E 'ros-\$\{ROS_DISTRO\}-realsense2-(camera|description)' "${DOCKERFILE}"
    refute_output --partial 'ros-${ROS_DISTRO}-realsense2-camera'
    refute_output --partial 'ros-${ROS_DISTRO}-realsense2-description'
}

@test "version ARGs are pinned, not floating (#97)" {
    # #97: the source build must pin concrete upstream tags (reproducible,
    # no auto-shipping upstream regressions) -- never `latest`.
    assert_file_exists "${DOCKERFILE}"
    run grep -F 'ARG LIBREALSENSE_VERSION="v2.58.2"' "${DOCKERFILE}"
    assert_success
    run grep -F 'ARG REALSENSE_ROS_VERSION="4.58.2"' "${DOCKERFILE}"
    assert_success
}

@test "runtime-test smoke asserts the ament marker (#97)" {
    # #97: a missed ament marker from the DESTDIR staging would leave the libs
    # present but `ros2 pkg prefix` failing; the runtime smoke must catch it.
    assert_file_exists "${DOCKERFILE}"
    run grep -F 'ros2 pkg prefix realsense2_camera' "${DOCKERFILE}"
    assert_success
}

@test "runtime rosdep skips the self-built SDK and resolves exec deps only (#97)" {
    # #97: runtime resolves exec ROS deps online but must NOT let rosdep
    # apt-install librealsense2 on top of the source build. The rosdep
    # invocation spans two Dockerfile lines, so assert each token is present.
    assert_file_exists "${DOCKERFILE}"
    run grep -F -- 'rosdep install -i --from-path /tmp/rs-src' "${DOCKERFILE}"
    assert_success
    run grep -F -- '--dependency-types=exec --skip-keys=librealsense2' "${DOCKERFILE}"
    assert_success
}
