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
