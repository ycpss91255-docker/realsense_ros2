# TEST.md

**67 tests** total.

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
| `realsense2_camera is installed` | `ros-${ROS_DISTRO}-realsense2-camera` package installed |
| `realsense2_description is installed` | `ros-${ROS_DISTRO}-realsense2-description` package installed |
| `RealSense SDK tool libraries resolve (rs-enumerate-devices)` | SDK CLI tool's shared libraries (librealsense2.so) all resolve via ldd with ROS sourced |

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

### System (9)

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

### Workspace (1)

| Test | Description |
|------|-------------|
| `Work directory exists` | `${HOME}/work` directory exists |

## test/smoke/install_udev_rules.bats

### install_udev_rules.sh (4)

| Test | Description |
|------|-------------|
| `install_udev_rules.sh -h exits 0` | Help exits successfully |
| `install_udev_rules.sh --help exits 0` | Help exits successfully |
| `install_udev_rules.sh -h prints usage` | Help output contains "Usage:" |
| `install_udev_rules.sh is executable` | Script carries the executable bit so the documented `./script/install_udev_rules.sh` works |

## test/smoke/dockerfile_guards.bats

### Dockerfile static guards (#71) (2)

| Test | Description |
|------|-------------|
| `groupadd new-group branch names the group after ${GROUP}, not ${USER} (#71)` | Dockerfile creates the new group named after USER_GROUP |
| `runtime-test ldd smoke covers symlinks, not just regular files (#71)` | runtime-test find includes `-type l` so symlinked libs are ldd-checked |

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
