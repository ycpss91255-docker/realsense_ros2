#!/usr/bin/env bats

setup() {
    load "${BATS_TEST_DIRNAME}/test_helper"
}

# -------------------- install_udev_rules.sh --------------------
# The repo's host-side udev-rules installer. ShellCheck runs over it via the
# lint stage; here we assert its --help contract plus the pure guards
# (run_privileged / arg + RULES_SRC validation). The privileged install steps
# need a host udevd unavailable in the build sandbox, so those are not run.

@test "install_udev_rules.sh -h exits 0" {
    run bash /lint/install_udev_rules.sh -h
    assert_success
}

@test "install_udev_rules.sh --help exits 0" {
    run bash /lint/install_udev_rules.sh --help
    assert_success
}

@test "install_udev_rules.sh -h prints usage" {
    run bash /lint/install_udev_rules.sh -h
    assert_line --partial "Usage:"
}

# Regression: the README documents `./script/install_udev_rules.sh` (direct
# execution), so the file must carry the executable bit. It shipped as 0644
# once, which made the documented command fail with "Permission denied" on a
# fresh clone. COPY preserves the source mode, so a 0644 regression surfaces
# here.
@test "install_udev_rules.sh is executable" {
    [ -x /lint/install_udev_rules.sh ]
}

@test "install_udev_rules.sh rejects an unknown argument with usage (exit 1)" {
    run bash /lint/install_udev_rules.sh --bogus
    assert_failure
    assert_line --partial "unknown argument"
    assert_line --partial "Usage:"
}

@test "install_udev_rules.sh fails when the rules source is missing (exit 1)" {
    # Run directly: SCRIPT_DIR resolves to /lint, so RULES_SRC points at
    # /config/realsense/official/99-realsense-libusb.rules, which is not copied
    # into the image -> the [ -f RULES_SRC ] guard returns 1 before any
    # privileged step.
    run bash /lint/install_udev_rules.sh
    assert_failure
    assert_line --partial "rules file not found"
}

@test "run_privileged runs the command directly when root (EUID=0)" {
    # Exercise the EUID -eq 0 branch by sourcing under sudo (EUID becomes 0):
    # the command must run directly, not via sudo.
    run sudo bash -c 'source /lint/install_udev_rules.sh; run_privileged echo RAN_DIRECT'
    assert_success
    assert_output --partial "RAN_DIRECT"
}

@test "run_privileged fails when non-root with no sudo available (exit 1)" {
    # Non-root (the bats user) + no sudo on PATH -> neither branch is possible.
    # Strip PATH only for the run_privileged call so sourcing (dirname/pwd) still
    # works; command -v sudo then finds nothing.
    run bash -c 'source /lint/install_udev_rules.sh; PATH= run_privileged true'
    assert_failure
    assert_line --partial "must run as root or have sudo"
}

# -------------------- check_udev_rules_sync.sh --------------------
# The udev-rules drift guard (#88): flags the vendored rules missing a device
# the pinned librealsense SDK tag ships. Only the --help contract is exercised
# here; the network diff is offline-skipped and not run in bats.

@test "check_udev_rules_sync.sh -h exits 0" {
    run bash /lint/check_udev_rules_sync.sh -h
    assert_success
}

@test "check_udev_rules_sync.sh --help exits 0" {
    run bash /lint/check_udev_rules_sync.sh --help
    assert_success
}

@test "check_udev_rules_sync.sh -h prints usage" {
    run bash /lint/check_udev_rules_sync.sh -h
    assert_line --partial "Usage:"
}

@test "check_udev_rules_sync.sh is executable" {
    [ -x /lint/check_udev_rules_sync.sh ]
}
