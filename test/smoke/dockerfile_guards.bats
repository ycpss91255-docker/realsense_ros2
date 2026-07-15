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

@test "version pins are concrete, not floating (#97, #130)" {
    # #97: the source build must pin concrete upstream tags (reproducible,
    # no auto-shipping upstream regressions) -- never `latest`.
    # #130: the librealsense pin's canonical home is setup.conf; assert it
    # carries a concrete vX.Y.Z there. The Dockerfile ARG stays a concrete
    # fallback (a bare `docker build` must still resolve a version), and
    # REALSENSE_ROS_VERSION stays a concrete Dockerfile ARG.
    assert_file_exists /lint/setup.conf
    run grep -oP '^\s*arg_[0-9]+\s*=\s*LIBREALSENSE_VERSION=\K\S+' /lint/setup.conf
    assert_success
    assert_output --regexp '^v[0-9]+\.[0-9]+\.[0-9]+$'

    assert_file_exists "${DOCKERFILE}"
    run grep -oP 'ARG LIBREALSENSE_VERSION="\K[^"]+' "${DOCKERFILE}"
    assert_success
    assert_output --regexp '^v[0-9]+\.[0-9]+\.[0-9]+$'
    run grep -oP 'ARG REALSENSE_ROS_VERSION="\K[^"]+' "${DOCKERFILE}"
    assert_success
    assert_output --regexp '^[0-9]+\.[0-9]+\.[0-9]+$'
}

@test "main.yaml derives the librealsense version from setup.conf, no hardcoded literal (#130)" {
    # #130 drift fix: CI must NOT hardcode a librealsense:v2.x literal (the bump
    # script never rewrote main.yaml, so a bump left CI FROMing the stale GHCR
    # image). It must instead reference the resolve step that parses setup.conf.
    assert_file_exists /lint/main.yaml
    run grep -E 'librealsense:v2\.[0-9]' /lint/main.yaml
    assert_failure
    run grep -F 'needs.resolve-librealsense.outputs.version' /lint/main.yaml
    assert_success
    run grep -F 'config/docker/setup.conf' /lint/main.yaml
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

@test "local librealsense SDK tag is version-scoped (Dockerfile default + hook agree)" {
    # A bare `librealsense:local` default lets ros1 (v2.55.1) and ros2 (v2.58.2)
    # clobber one shared local tag, so a later local build silently FROMs the
    # wrong-version SDK. The Dockerfile FROM default and the pre-build hook must
    # both derive the SAME `librealsense:<version>-<codename>` tag.
    assert_file_exists "${DOCKERFILE}"
    run grep -F -- 'ARG LIBREALSENSE_IMAGE="librealsense:${LIBREALSENSE_VERSION}-${UBUNTU_CODENAME}"' "${DOCKERFILE}"
    assert_success
    run grep -F -- '-t "librealsense:${librealsense_version}-${ubuntu_codename}"' /lint/hooks-pre-build.sh
    assert_success
}

@test "the bare librealsense:local tag is gone (a wrong version fails the build, not runs silently)" {
    # Regression: with a bare tag a wrong/mismatched version is silent (the tag
    # exists, holds the wrong SDK). Version-scoping makes a wrong/missing version a
    # nonexistent tag, so FROM ${LIBREALSENSE_IMAGE} fails loudly -- docker resolves
    # the missing tag to a docker.io pull that 404s and aborts the build.
    assert_file_exists "${DOCKERFILE}"
    run grep -F -- 'ARG LIBREALSENSE_IMAGE="librealsense:local"' "${DOCKERFILE}"
    assert_failure
    run grep -F -- '-t librealsense:local' /lint/hooks-pre-build.sh
    assert_failure
}
