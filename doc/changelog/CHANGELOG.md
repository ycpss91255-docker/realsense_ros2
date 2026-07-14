# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Version-scoped the local librealsense SDK image tag (refs #125, base#828): the
  pre-build hook and the Dockerfile `LIBREALSENSE_IMAGE` default used a bare
  `librealsense:local`, which ros1 (v2.55.1) and ros2 (v2.58.2) share -- building
  one repo clobbered the other's local SDK image and a later build silently FROMed
  the wrong-version SDK. Both now derive `librealsense:${LIBREALSENSE_VERSION}-${UBUNTU_CODENAME}`,
  so the tags never collide and a wrong/missing version fails the `FROM` loudly.
  The pre-build hook is now also COPYed into `/lint` so ShellCheck covers it (it
  previously escaped the non-recursive `script/*.sh` glob). Added two
  `dockerfile_guards.bats` regressions.

### Changed
- Flattened the `config/realsense/` audience sub-level: camera profiles moved
  from `config/realsense/yaml/custom/*.yaml` to `config/realsense/yaml/*.yaml`,
  and the D500 example tables from `config/realsense/json/official/d500_tables/`
  to `config/realsense/json/d500_tables/`. The `camera.yaml` symlink, Dockerfile
  `CAMERA_CONFIG` prose, scripts, and READMEs (4 languages) follow the new
  paths. Refs #123 / base#827.
- Moved the vendored realsense-ros **drift baseline** out of `config/`:
  `config/realsense/yaml/official/{config.yaml,global_settings.yaml}` ->
  `.github/upstream-baseline/{config.yaml,global_settings.yaml}`. These are a CI
  drift fixture (checked by `script/check_configs_sync.sh` and annotated by
  `.github/workflows/upstream-bump.yaml`), not user config, and are not baked
  into the image. Interim best-guess layout pending base#827. Refs #123 /
  base#827.

### Added
- Optional **camera config** selected by the root `camera.yaml` symlink
  (modeled on `app/ros1_bridge`'s `bridge.yaml`). The Dockerfile
  (`ARG CAMERA_CONFIG="camera.yaml"` + `COPY --chmod=0644 "${CAMERA_CONFIG}"
  /camera_config.yaml`, both the `devel` and `runtime` stages) follows the
  symlink and copies its target's content; the entrypoint launches
  `ros2 launch realsense2_camera rs_launch.py config_file:=/camera_config.yaml
  initial_reset:=true` when that file is non-empty, otherwise runs the stock
  default `CMD` unchanged. The default target
  `config/realsense/yaml/none.yaml` is an empty file, so the out-of-the-box
  behavior is exactly the stock upstream default (640x480x30, aligned).
  Activate a profile by repointing the symlink or passing
  `--build-arg CAMERA_CONFIG=config/realsense/yaml/usb2_640x480p15fps.yaml`.
- **Camera profile presets** under `config/realsense/yaml/` (one file per
  resolution at that link's max fps; depth always 1280x720, capped at 30 fps;
  infra/IMU off; aligned depth on): four USB3 presets enumerated on a D455
  (`usb3_1280x720p30fps`, `usb3_848x480p60fps`, `usb3_640x480p60fps`,
  `usb3_424x240p90fps`) and three **UNVERIFIED** USB2 presets
  (`usb2_1280x720p6fps`, `usb2_640x480p15fps`, `usb2_424x240p30fps`; the USB2
  whitelist was not enumerated -- verify 720p depth on a real USB2 link), plus
  `none.yaml` (empty stock marker). Refs #121.
- Vendored upstream files under `.github/upstream-baseline/`,
  `config/realsense/json/d500_tables/`, and `config/realsense/udev/`
  (`config.yaml`, `global_settings.yaml`, `d500_tables/*.json` from
  realsense-ros, and the `99-realsense-libusb.rules` udev rules vendored from
  the librealsense SDK), kept separate from our
  `config/realsense/yaml/` profiles; provenance and the vendored-vs-custom
  split are documented in the repo README (Camera Config section, with i18n),
  and `script/check_configs_sync.sh` + a `check-configs` job in
  `.github/workflows/upstream-bump.yaml` that diffs them against upstream at
  the pinned `REALSENSE_ROS_VERSION` and annotates a `::warning` on drift
  (mirrors the udev-rules drift job; advisory only, no auto-PR).
- `test/smoke/camera_config.bats` (5 tests): asserts the `camera.yaml` symlink
  resolves into the image, the default config is empty, and the entrypoint /
  Dockerfile carry the `[ -s ]` config-file wiring.
- `script/hooks/pre/build.sh` (base #440 pre-build hook): for a local
  `just build` / `./build.sh` (with `LIBREALSENSE_IMAGE` unset) it auto-builds
  `librealsense:local` from `docker/Dockerfile.librealsense` before the main
  build, mirroring how `build.sh` auto-builds `test-tools:local`. The local
  build is now self-contained -- no GHCR pull needed. If `LIBREALSENSE_IMAGE`
  is already set (CI passes the GHCR tag) the hook is a no-op.
- `docker/Dockerfile.librealsense` gains a `test` stage (publish-time smoke
  GATE: asserts the `/rs-full` + `/rs-stage` trees exist, `librealsense2.so` is
  present and fully linkable with no `not found`, the versioned soname is
  present, and `/rs-stage` is pruned of the viewer / `rs-*` tools / GL lib) and
  a `scratch`-based `export` stage. `build-librealsense.yaml` now builds
  `--target test` (push=false) as a gate BEFORE publishing, so a broken SDK
  never reaches GHCR.
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
  `config/realsense/udev/99-realsense-libusb.rules` against upstream at the pinned
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
- Behavioral smoke coverage for the repo's helper scripts. `entrypoint.sh`,
  `install_udev_rules.sh`, `check_configs_sync.sh` and `bump_realsense_versions.sh`
  gained a `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` source-guard (behavior-neutral:
  the real entrypoint still sources ROS and execs the CMD unchanged) so their pure
  functions are unit-testable. `entrypoint.sh` factors the camera-config gate into
  `_apply_camera_config` (resolving `CONFIGURED_ARGV` without executing).
  `test/smoke/camera_config.bats` now exercises the gate behaviorally (empty vs
  active config, `ros2 launch` vs `bash` / `ros2 run`); new
  `test/smoke/check_configs_sync.bats` and `test/smoke/bump_realsense_versions.bats`
  cover the CMake `use_lifecycle_node` parser and the ARG read/rewrite helpers;
  `test/smoke/install_udev_rules.bats` adds the `check_udev_rules_sync.sh` help
  block and `run_privileged` / arg-guard error branches; `test/smoke/ros_env.bats`
  asserts the baked config + udev-rules file modes. Smoke total 75 -> 99.

### Changed
- **`config/realsense/` restructured type-first** into `yaml/{official,custom}/`,
  `json/official/`, and `udev/` (was `official/` + `custom/`). Vendored configs
  now live under `yaml/official/`, the D500 JSON tables under
  `json/official/d500_tables/`, and the udev rules under `udev/`; all references
  (Dockerfile COPYs, `check_configs_sync.sh`, `check_udev_rules_sync.sh`,
  `install_udev_rules.sh`, entrypoint, tests, `upstream-bump.yaml`) were repointed.
  Refs #121.
- `usb2_640x480p15fps.yaml` (renamed from `usb2.yaml`) now carries depth
  1280x720x15 (was 480x270x15), following the locked rule that depth always uses
  the camera's highest resolution. Refs #121.
- librealsense is now consumed from a parameterized prebuilt SDK image instead
  of compiled inline in the main `devel` stage. The main Dockerfile adds a
  global `ARG LIBREALSENSE_IMAGE="librealsense:local"` + `FROM ${LIBREALSENSE_IMAGE}
  AS rs_sdk` and COPYs the prebuilt `/rs-full` + `/rs-stage` trees in before the
  colcon wrapper build (which is unchanged), dropping the ~15-25 min
  librealsense compile from every build. This mirrors base's `TEST_TOOLS_IMAGE`
  dual-source pattern: local builds FROM `librealsense:local` (built by the
  pre-build hook, no GHCR), CI passes
  `LIBREALSENSE_IMAGE=ghcr.io/ycpss91255-docker/librealsense:v2.58.2-<codename>`
  per matrix Ubuntu codename so buildx PULLS the prebuilt SDK. `main.yaml` wires
  the per-codename tag through `build_args`.
- The prebuilt `librealsense` SDK image is ROS-agnostic and keyed on the Ubuntu
  platform, not the ROS distro. It builds on `ubuntu:<codename>` and installs
  into the `/usr/local` prefix (the consumer COPYs it there and runs `ldconfig`;
  the realsense-ros wrapper still lands in `/opt/ros/<distro>`), and its image
  tag is `v2.58.2-jammy` / `v2.58.2-noble` rather than `<distro>-v2.58.2`, since
  librealsense2 is a pure C++ library whose `.so` is ABI-bound to the Ubuntu
  release's glibc/libstdc++, not to ROS. The leaner `ubuntu` base also needs two
  things `ros-base` provided for free: `ca-certificates` (installed explicitly,
  for the https SDK clone) and `DEBIAN_FRONTEND=noninteractive` on the apt
  install (the GTK/GL deps pull in `tzdata`, which would otherwise prompt
  interactively and hang the TTY-less build).
- The published `librealsense` SDK image is now the slim `scratch`-based
  `export` target -- literally just the `/rs-full` + `/rs-stage` trees, with the
  Ubuntu base + build-deps dropped (the consumer only COPYs those trees).
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

