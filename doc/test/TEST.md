# TEST.md

**57 tests** total.

## test/smoke/ros_env.bats

### ROS environment (3)

| Test | Description |
|------|-------------|
| `ROS_DISTRO is set` | ROS_DISTRO environment variable is set |
| `ROS 2 setup.bash exists` | `/opt/ros/${ROS_DISTRO}/setup.bash` exists |
| `ROS 2 setup.bash can be sourced` | ROS 2 setup script sources without error |

### RealSense packages (2)

| Test | Description |
|------|-------------|
| `realsense2_camera is installed` | `ros-${ROS_DISTRO}-realsense2-camera` package installed |
| `realsense2_description is installed` | `ros-${ROS_DISTRO}-realsense2-description` package installed |

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
