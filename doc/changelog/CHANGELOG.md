# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Bundle the Intel RealSense D400 Series Dynamic Calibration Tool
  (`librscalibrationtool`) in the `devel` image, pulled from Intel's librealsense
  apt repo in the `devel-base` stage (amd64-only; skipped on other architectures).
  Provides `Intel.Realsense.DynamicCalibrator` / `Intel.Realsense.CustomRW` for
  target-based extrinsic calibration (rectification, depth scale, and the RGB
  extrinsics on RGB devices). Documented in
  the new `doc/CALIBRATION.md` (linked from `README.md` + 3 translated READMEs).
- `script/install_udev_rules.sh`: one-shot installer that copies the bundled
  RealSense udev rules to the **host** `/etc/udev/rules.d/` and reloads udev.
  The in-image rules alone are not enough (the container has no `udevd`); without
  the host rules the non-root container user cannot open the raw USB node and the
  SDK misdetects the camera (USB 2.0 / `Product Line not supported` / firmware
  update failures, see IntelRealSense/librealsense#12022). Documented in
  `README.md` + 3 translated READMEs; covered by `test/smoke/install_udev_rules.bats`.
- `LICENSE` (Apache 2.0) and CI / License badges in
  `README.md` + 3 translated READMEs (#41). Fresh add
  -- repo previously had no LICENSE and no badges. Aligns with
  the org-wide Apache 2.0 migration tracked across 17 sister
  repos.

### Changed
- Move `CAMERA.md` from `doc/test/` to `doc/` (it documents manual physical-camera
  use, not build-time tests); README links + directory trees updated in 4 languages.
- Add an "On-chip calibration" section to `doc/CAMERA.md` covering the
  realsense-viewer workflow and how to read the health-check score (absolute value
  vs the 0.25 threshold; sign is direction, not pass/fail).

### Fixed
- CI now actually builds **both** `linux/amd64` and `linux/arm64`, making good
  on the README's long-standing multi-arch claim (previously only amd64 was
  built despite the claim, #72). Achieved by passing
  `platforms: linux/amd64,linux/arm64` to the base build-worker (each arch runs
  on its native runner -- arm64 on `ubuntu-24.04-arm`, no QEMU) and by migrating
  the `Dockerfile` off its bespoke `bats-src` / `bats-extensions` / `lint-tools`
  stages onto the template's canonical `COPY --from=${TEST_TOOLS_IMAGE}` pattern
  (pinned `test_tools_version: v0.41.0`). The pre-built test-tools image is
  multi-arch, so the lint/bats binaries now match the build platform instead of
  always being x86_64 -- this is what actually unblocked arm64 (the old
  hand-rolled `lint-tools` stage hardcoded x86_64 shellcheck/hadolint URLs). The
  full pipeline (devel-test lint + 66 bats smoke, runtime-test ldd) was verified
  green on native arm64 hardware (Raspberry Pi 5). The bundled Dynamic
  Calibration Tool stays amd64-only and is skipped on arm64 as before.
- `config/docker/setup.conf`: remove the dead `cap_add`
  (`SYS_ADMIN`/`NET_ADMIN`/`MKNOD`) and `security_opt` (`seccomp:unconfined`)
  entries -- under `privileged=true` they are no-ops (#70). Move `/dev` from a
  `[devices]` snapshot to a `[volumes]` live bind so hot-plug / firmware-DFU
  re-enumeration is visible without a container restart. `privileged=true` is
  kept and documented: hardware testing confirmed the full D455 feature set
  needs it (V4L2 needs the whole dynamically-renumbered `/dev`; the HID/IIO IMU
  needs writable `/sys` + AppArmor-unconfined + a dynamic iio-major device).
  Rationale recorded in `doc/adr/00000001-realsense-requires-privileged.md`
  (this repo's first ADR).
- `Dockerfile`: the new-group branch now runs `groupadd -g ${GID} ${GROUP}`
  instead of `${USER}`, so the created group is named after `USER_GROUP` rather
  than the user; previously harmless only because `USER == GROUP` by default,
  a real bug once they differ. The `runtime-test` ldd smoke now finds
  `-type f -o -type l`, so a packaged tool/lib shipped as a symlink to a
  versioned `.so` is ldd-checked too (#71). Guarded by
  `test/smoke/dockerfile_guards.bats`.
- revert display mount to XDG_RUNTIME_DIR:rw
- use tmpfs for XDG_RUNTIME_DIR + Wayland socket mount

### Changed
- Rename repo from `realsense_humble` to `realsense_ros2`; migrate the
  user-facing wrapper entry point from the GNU `make` targets to `just`
  recipes (justfile symlinked to `.base/script/docker/justfile`), forwarding
  1:1 to `script/<wrapper>.sh`.
- Align README.md to template framework: move H1 above the language switch link, add CI status badge, promote TL;DR blockquote to `## TL;DR` H2, add `## Overview` section, extend Table of Contents. Translations untouched.

## [v2.0.0] - 2026-03-28

### Added
- migrate from docker_setup_helper to template
- add Wayland display support for X11/Wayland dual compatibility

### Changed
- remove docker_setup_helper subtree and local CI workflows
- upgrade to full env-level architecture
- add docker_setup_helper subtree
- Squashed 'docker_setup_helper/' content from commit 0141a19
- upgrade to full multi-stage architecture

### Fixed
- create udev rules directory before COPY

## [v1.0.0] - 2026-03-25

### Added
- initial realsense_humble repo

### Fixed
- remove wildcard apt install and use dpkg for smoke tests

