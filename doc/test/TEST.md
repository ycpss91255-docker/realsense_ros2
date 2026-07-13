# TEST.md

**99 tests** total.

## test/smoke/ros_env.bats

### ROS environment (4)

| Test | Description |
|------|-------------|
| `ROS_DISTRO is set` | ROS_DISTRO environment variable is set |
| `ROS 2 setup.bash exists` | `/opt/ros/${ROS_DISTRO}/setup.bash` exists |
| `ROS 2 setup.bash can be sourced` | ROS 2 setup script sources without error |
| `interactive shells source ROS (ros2 on PATH via bashrc.d)` | `config/shell/bashrc.d/10-ros-source.sh` puts `ros2` on PATH for interactive shells |

### RealSense packages (3)

| Test | Description |
|------|-------------|
| `realsense2_camera is discoverable via ament index (source build)` | `realsense2_camera` ament marker present under `/opt/ros/${ROS_DISTRO}` (built from pinned source, #97) |
| `realsense2_description is discoverable via ament index (source build)` | `realsense2_description` ament marker present under `/opt/ros/${ROS_DISTRO}` (bundled in realsense-ros source, #97) |
| `RealSense SDK tool libraries resolve (rs-enumerate-devices)` | `/usr/local/bin` SDK CLI tool's shared libraries (librealsense2.so) all resolve via ldd (ldconfig registers /usr/local/lib) |

### Desktop GUI (devel) (2)

| Test | Description |
|------|-------------|
| `ROS 2 desktop is installed (rviz2 on PATH)` | `ros-${ROS_DISTRO}-desktop` provides rviz2 in the devel image |
| `Qt xcb platform plugin is present (realsense-viewer / rviz2 GUI)` | `libqxcb.so` present so Qt GUI tools can open a window |

### Base tools (4)

| Test | Description |
|------|-------------|
| `git is available` | git command works |
| `vim is available` | vim command works |
| `sudo is available` | sudo command works |
| `sudo passwordless works` | sudo runs without password |

### System (11)

| Test | Description |
|------|-------------|
| `User is not root` | Container user is not root |
| `HOME is set and exists` | HOME is set and directory exists |
| `container user matches the configured USER_NAME (base v0.41.0 build contract)` | Container user matches configured USER_NAME |
| `HOME path matches the container user` | HOME path matches the container user |
| `Timezone is Asia/Taipei` | Timezone configured correctly |
| `LANG is en_US.UTF-8` | LANG locale set |
| `LC_ALL is en_US.UTF-8` | LC_ALL locale set |
| `entrypoint.sh exists and executable` | `/entrypoint.sh` is executable |
| `RealSense udev rules exist` | udev rules file exists |
| `camera config is mode 0644 and readable by the container user` | `/camera_config.yaml` is mode 0644 and readable so the non-root entrypoint can read an active profile |
| `RealSense udev rules are mode 0644` | Vendored udev rules file is mode 0644 (world-readable, as udev requires) |

### Workspace (1)

| Test | Description |
|------|-------------|
| `Work directory exists` | `${HOME}/work` directory exists |

## test/smoke/install_udev_rules.bats

### install_udev_rules.sh (8)

| Test | Description |
|------|-------------|
| `install_udev_rules.sh -h exits 0` | Help exits successfully |
| `install_udev_rules.sh --help exits 0` | Help exits successfully |
| `install_udev_rules.sh -h prints usage` | Help output contains "Usage:" |
| `install_udev_rules.sh is executable` | Script carries the executable bit (documented direct-run) |
| `install_udev_rules.sh rejects an unknown argument with usage (exit 1)` | Unknown arg prints usage and exits 1 |
| `install_udev_rules.sh fails when the rules source is missing (exit 1)` | Missing RULES_SRC guard returns 1 before any privileged step |
| `run_privileged runs the command directly when root (EUID=0)` | Root branch runs the command directly (sourced under sudo) |
| `run_privileged fails when non-root with no sudo available (exit 1)` | Non-root + no sudo on PATH returns 1 with an error |

### check_udev_rules_sync.sh (4)

| Test | Description |
|------|-------------|
| `check_udev_rules_sync.sh -h exits 0` | Help exits successfully |
| `check_udev_rules_sync.sh --help exits 0` | Help exits successfully |
| `check_udev_rules_sync.sh -h prints usage` | Help output contains "Usage:" |
| `check_udev_rules_sync.sh is executable` | Script carries the executable bit |

## test/smoke/check_configs_sync.bats

### check_configs_sync.sh (6)

| Test | Description |
|------|-------------|
| `check_configs_sync.sh -h exits 0` | Help exits successfully |
| `check_configs_sync.sh --help exits 0` | Help exits successfully |
| `check_configs_sync.sh -h prints usage` | Help output contains "Usage:" |
| `check_configs_sync.sh is executable` | Script carries the executable bit |
| `extract_global_default reads the OFF (else) branch default from CMakeLists` | Parser returns `use_lifecycle_node: false` from a fixture with the USE_LIFECYCLE_NODE block |
| `extract_global_default returns nothing when the block is absent (drift path)` | Parser returns empty when the block is missing (drift) |

## test/smoke/bump_realsense_versions.bats

### bump_realsense_versions.sh (6)

| Test | Description |
|------|-------------|
| `bump_realsense_versions.sh -h exits 0` | Help exits successfully |
| `bump_realsense_versions.sh --help exits 0` | Help exits successfully |
| `bump_realsense_versions.sh -h prints usage` | Help output contains "Usage:" |
| `bump_realsense_versions.sh is executable` | Script carries the executable bit |
| `current_arg returns the pinned value from the Dockerfile ARG` | Parser reads a pinned ARG value from a fixture Dockerfile |
| `set_arg rewrites only the target ARG line (round-trip; others untouched)` | Rewriter updates the target ARG and leaves other ARG lines unchanged |

## test/smoke/dockerfile_guards.bats

### Dockerfile static guards (6)

| Test | Description |
|------|-------------|
| `groupadd new-group branch names the group after ${GROUP}, not ${USER} (#71)` | Dockerfile creates the new group named after USER_GROUP |
| `runtime-test ldd smoke covers symlinks, not just regular files (#71)` | runtime-test find includes `-type l` so symlinked libs are ldd-checked |
| `devel-base/runtime no longer apt-install the RealSense packages (#97)` | The apt `realsense2-camera` / `-description` installs are gone (source build) |
| `version ARGs are pinned, not floating (#97)` | `LIBREALSENSE_VERSION=v2.58.2` / `REALSENSE_ROS_VERSION=4.58.2` pinned, not `latest` |
| `runtime-test smoke asserts the ament marker (#97)` | runtime smoke runs `ros2 pkg prefix realsense2_camera` to catch a missed marker |
| `runtime rosdep skips the self-built SDK and resolves exec deps only (#97)` | runtime rosdep uses `--dependency-types=exec --skip-keys=librealsense2` |

## test/smoke/camera_config.bats

### Camera-config wiring (6)

| Test | Description |
|------|-------------|
| `camera.yaml symlink resolved into the image (/camera_config.yaml exists)` | Docker COPY followed the root `camera.yaml` symlink; `/camera_config.yaml` is present |
| `default baked camera config is empty (stock upstream default)` | Default target `config/realsense/yaml/custom/none.yaml` is 0 bytes so the `[ -s ]` guard is false |
| `entrypoint leaves the stock launch unchanged for an empty config` | `_apply_camera_config` leaves the `ros2 launch` argv untouched when the config is empty |
| `entrypoint applies config_file:= for a non-empty camera config` | `_apply_camera_config` resolves `config_file:=` + `initial_reset:=true` on an active config |
| `entrypoint does not hijack a non-launch command even with a config` | A baked profile does not turn the devel `bash` CMD into a camera launch |
| `entrypoint does not hijack ros2 run (only ros2 launch) even with a config` | `ros2 run ...` passes through unchanged; only `ros2 launch` is gated |

## .base/test/smoke/script_help.bats

### build.sh (4)

| Test | Description |
|------|-------------|
| `build.sh -h exits 0` | Help exits successfully |
| `build.sh --help exits 0` | Help exits successfully |
| `build.sh -h prints usage` | Help output contains "Usage:" |
| `build.sh -h describes auto-apply default (no stale 'warn on drift', #365)` | Help describes auto-apply default |

### run.sh (4)

| Test | Description |
|------|-------------|
| `run.sh -h exits 0` | Help exits successfully |
| `run.sh --help exits 0` | Help exits successfully |
| `run.sh -h prints usage` | Help output contains "Usage:" |
| `run.sh -h describes auto-apply default (no stale 'warn on drift', #365)` | Help describes auto-apply default |

### exec.sh (3)

| Test | Description |
|------|-------------|
| `exec.sh -h exits 0` | Help exits successfully |
| `exec.sh --help exits 0` | Help exits successfully |
| `exec.sh -h prints usage` | Help output contains "Usage:" |

### stop.sh (3)

| Test | Description |
|------|-------------|
| `stop.sh -h exits 0` | Help exits successfully |
| `stop.sh --help exits 0` | Help exits successfully |
| `stop.sh -h prints usage` | Help output contains "Usage:" |

### LANG auto-detect (4)

| Test | Description |
|------|-------------|
| `build.sh detects zh from LANG=zh_TW.UTF-8` | Detects Traditional Chinese |
| `build.sh detects ja from LANG=ja_JP.UTF-8` | Detects Japanese |
| `build.sh defaults to en for LANG=en_US.UTF-8` | Defaults to English |
| `build.sh SETUP_LANG overrides LANG` | SETUP_LANG takes priority |

### Help --lang override (9)

| Test | Description |
|------|-------------|
| `build.sh --help --lang zh-TW prints zh-TW usage (#222)` | build.sh zh-TW help |
| `build.sh --help --lang zh-CN prints zh-CN usage (#222)` | build.sh zh-CN help |
| `build.sh --help --lang ja prints ja usage (#222)` | build.sh ja help |
| `run.sh --help --lang zh-TW prints zh-TW usage (#222)` | run.sh zh-TW help |
| `run.sh --help --lang ja prints ja usage (#222)` | run.sh ja help |
| `exec.sh --help --lang zh-TW prints zh-TW usage (#222)` | exec.sh zh-TW help |
| `exec.sh --help --lang ja prints ja usage (#222)` | exec.sh ja help |
| `stop.sh --help --lang zh-TW prints zh-TW usage (#222)` | stop.sh zh-TW help |
| `stop.sh --help --lang ja prints ja usage (#222)` | stop.sh ja help |

## .base/test/smoke/display_env.bats

### Wayland env vars (3)

| Test | Description |
|------|-------------|
| `compose.yaml contains WAYLAND_DISPLAY env` | WAYLAND_DISPLAY in compose.yaml |
| `compose.yaml contains XDG_RUNTIME_DIR env` | XDG_RUNTIME_DIR in compose.yaml |
| `compose.yaml contains XAUTHORITY env` | XAUTHORITY in compose.yaml |

### Display mounts (4)

| Test | Description |
|------|-------------|
| `compose.yaml mounts XDG_RUNTIME_DIR as rw` | XDG_RUNTIME_DIR mounted read-write |
| `compose.yaml mounts XAUTHORITY volume` | XAUTHORITY volume mounted |
| `compose.yaml has no consecutive duplicate keys` | No YAML duplicate key errors |
| `compose.yaml mounts X11-unix volume` | X11 socket mounted |

### xhost branching (4)

| Test | Description |
|------|-------------|
| `run.sh contains XDG_SESSION_TYPE check` | Session type detection present |
| `run.sh calls xhost +SI:localuser on wayland` | Wayland xhost command correct |
| `run.sh calls xhost +local: on X11` | X11 xhost command correct |
| `run.sh defaults to X11 xhost when XDG_SESSION_TYPE unset` | Falls back to X11 |
