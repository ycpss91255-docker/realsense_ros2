# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Publish-time `test` stage in `docker/librealsense/Dockerfile` gating the
  prebuilt librealsense SDK image: the publish workflow builds `--target test`
  (`push: false`) BEFORE it pushes, so an SDK image whose `/rs-full` + `/rs-stage`
  DESTDIR trees are malformed can never reach GHCR. The stage asserts both trees
  exist, that `/rs-full` carries `librealsense2.so` with a fully-resolvable `ldd`
  and a versioned soname (`librealsense2.so.<major.minor>`), and that `/rs-stage`
  is correctly pruned (no `realsense-viewer`, no `rs-*` example tools, no
  `librealsense2-gl`). This stage IS the correctness contract of the trees the
  consumer COPYs (builds on #103).
- `LIBREALSENSE_VERSION=v2.58.2` / `REALSENSE_ROS_VERSION=4.58.2` build-args
  pinning the RealSense source build; override either with
  `--build-arg` (e.g. `just build --build-arg LIBREALSENSE_VERSION=v2.59.0`).
  Placed immediately before the compile RUN so unrelated edits stay
  buildx-cache-hot and only a version bump recompiles (#97).
- Scheduled `.github/workflows/upstream-bump.yaml` (weekly + `workflow_dispatch`)
  that opens a `chore(deps)` PR when a newer librealsense / realsense-ros
  release appears -- dependabot cannot see the ARG-embedded git tags, so this
  is a bespoke Action driven by `script/bump_realsense_versions.sh`. A second
  job runs `script/check_udev_rules_sync.sh` and annotates on drift (#97).
- `script/check_udev_rules_sync.sh`: diffs the vendored
  `config/realsense/99-realsense-libusb.rules` against upstream at the pinned
  `LIBREALSENSE_VERSION`; a provenance/sync header on the rules file documents
  the vendoring. The runtime smoke gains a `ros2 pkg prefix realsense2_camera`
  ament-marker check (catches a missed marker from the source-build staging) (#97).
- README **Multi-machine (ROS 2)** section (all 4 languages): consume the camera from another machine via DDS auto-discovery by setting a matching `ROS_DOMAIN_ID` in the `.env` workload overlay -- no master, no command-line flags, since `compose.yaml` injects `.env` via `env_file`. Documents the host-network / `ROS_LOCALHOST_ONLY` requirements and the best-effort-QoS frame-drop caveat. Verified across a Pi + host (~10 Hz over a direct link).
- README TL;DR + Quick Start now demonstrate the actual RGB-D **app**: `just run
  -t runtime` launches the camera node, with a CLI check (`ros2 topic hz` on the
  colour + depth topics) and a visual demo (`rqt_image_view` in the `devel`
  image) to see RGB + depth. Replaces the old `just build && just run`, which only
  opens the `devel` dev shell; clarifies `just run` (devel shell) vs `just run -t
  runtime` (the app). All 4 languages (#89).
- README **Prerequisites** (install Docker Engine + Compose plugin + `just`; plus
  host udev rules for a physical camera) and **Uninstall / Cleanup** (`just stop`,
  `just prune`, host udev-rule removal) sections, in all 4 languages (#85). The
  prior README assumed the `just` + `docker compose` toolchain was already
  present and never documented teardown; surfaced bringing the repo up on a fresh
  arm64 Raspberry Pi (Docker present but no Compose plugin, no `just`).
- CI now builds a **ROS 2 distro matrix -- Humble (Ubuntu 22.04 jammy) and
  Jazzy (Ubuntu 24.04 noble)** -- from a single Dockerfile, replacing the
  prior Humble-only build (#66). Each matrix entry passes
  `ROS_DISTRO` / `ROS_TAG` / `UBUNTU_CODENAME` and runs the full devel-test
  (lint + bats) and runtime-test (ldd) gate on both `linux/amd64` and
  `linux/arm64`. A stable-named `ci-passed` aggregator job fronts the matrix
  so branch protection's required status check no longer has to enumerate
  every entry. The Dynamic Calibration Tool now installs on **both** distros
  (amd64) via Intel's officially-documented direct-`.deb` method (`dpkg -i`):
  Intel lists Ubuntu 22.04 and 24.04 as supported, and the single
  Intel-hosted `.deb` (no apt `Depends`, links only forward-compatible
  standard libs) installs and runs on noble even though Intel does not index
  it in its noble apt repo. This also drops the previous Intel apt-repo +
  keyring setup. Still amd64-only (skipped on arm64).
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
- The published prebuilt librealsense SDK image is now the slim `scratch`
  `export` target -- literally just the `/rs-full` + `/rs-stage` DESTDIR trees a
  consumer COPYs out -- instead of the fat `build` image (ros-base + the full
  build toolchain underneath, which was dead weight since nothing runs the SDK
  image). Drops the published image from ~1.2 GB to ~90 MB. The publish
  workflow's build-and-push step now targets `export`; the trees are at the same
  paths, so any `COPY --from` against the image is unchanged (builds on #103).
- The `runtime` image now launches with `initial_reset:=true` by default: on the
  RSUSB userspace backend, a D455 cold-start on arm64 could wedge the first
  stream-open (`RS2_USB_STATUS_IO`, topics stuck at 0 Hz); resetting the device
  at startup clears it. `runtime` CMD only (so `devel` is unaffected), and the
  arg is overridable. Adds a few seconds to launch.
- RealSense components are now built from pinned source (librealsense SDK +
  realsense-ros wrapper) instead of apt. Removed the
  `ros-<distro>-realsense2-camera` / `-realsense2-description` apt installs from
  both `devel-base` and `runtime`; both now install into `/opt/ros/<distro>`
  (the ament path is unchanged, so entrypoint / bashrc / smoke paths are
  unchanged). `devel` compiles both at the pinned tags (with the SDK
  `BUILD_EXAMPLES` tools + RViz plugin); `runtime` COPYs the built libs +
  wrapper from `devel` (omission-proof per-package `cmake --install` DESTDIR
  staging, `bin/` tools excluded) and resolves its exec ROS deps online via
  `rosdep --dependency-types=exec --skip-keys=librealsense2`. The RSUSB
  (userspace) backend is forced, so no kernel patching is needed (#97).
- `runtime` image now aligns depth to colour by default: the default CMD switches
  from `rs_launch.py` to Intel's packaged `rs_align_depth_launch.py`, so a plain
  `just run -t runtime` additionally publishes
  `/camera/camera/aligned_depth_to_color/image_raw` (the aligned launch is a thin
  wrapper that sets `align_depth.enable` default true and delegates to
  `rs_launch.py`). Override the command to fall back to the non-aligned launch or
  pass other args (#94).
- Move `CAMERA.md` from `doc/test/` to `doc/` (it documents manual physical-camera
  use, not build-time tests); README links + directory trees updated in 4 languages.
- Add an "On-chip calibration" section to `doc/CAMERA.md` covering the
  realsense-viewer workflow and how to read the health-check score (absolute value
  vs the 0.25 threshold; sign is direction, not pass/fail).

### Fixed
- `runtime` image now sources ROS for interactive `docker exec` shells (appends a
  guarded `source /opt/ros/$ROS_DISTRO/setup.bash` to `/etc/bash.bashrc`), so
  `just exec -t runtime` / `docker exec -it <runtime> bash` has `ros2` on PATH
  with no manual source. The entrypoint sources ROS only for PID 1 (the launched
  app) and `docker exec` bypasses it; `devel` already did this via its bashrc.d
  drop-in. Interactive-only (non-interactive behavior unchanged), and no fragile
  per-arch/per-python ROS paths baked into `ENV` (#87, base#657).
- README architecture diagram + stage table (4 languages): refresh the stale
  `bats-src` / `bats-extensions` / `lint-tools` stages (removed in #72) to the
  canonical `test-tools-stage`, and show the multi-distro `sys` base image.
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

