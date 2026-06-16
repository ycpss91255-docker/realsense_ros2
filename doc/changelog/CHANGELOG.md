# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `LICENSE` (Apache 2.0) and CI / License badges in
  `README.md` + 3 translated READMEs (#41). Fresh add
  -- repo previously had no LICENSE and no badges. Aligns with
  the org-wide Apache 2.0 migration tracked across 17 sister
  repos.

### Fixed
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

