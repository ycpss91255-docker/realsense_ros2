#!/usr/bin/env bash
set -euo pipefail

# Source ROS 2. ROS's setup.bash chain dereferences unbound vars (e.g.
# AMENT_TRACE_SETUP_FILES), so bracket the source in set +u / set -u to
# isolate it from this script's strict mode -- the canonical pattern for
# sourcing third-party setup scripts (see ros1_bridge#81). Without this the
# entrypoint dies under nounset and the container exits immediately on
# `just run` (CI never catches it: the build-time RUN smoke bypasses
# ENTRYPOINT, so only an actual container start hits this path).
set +u
# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

# Optional camera config (modeled on ros1_bridge's /bridge.yaml). The Dockerfile
# COPYs the root `camera.yaml` symlink's target to /camera_config.yaml; the
# default target is config/realsense/custom/none.yaml, an EMPTY file, so the
# stock upstream default runs unchanged. When a non-empty profile is active
# (repoint the symlink or pass --build-arg CAMERA_CONFIG=...), launch the camera
# with it via rs_launch.py's config_file arg. Guarded on `ros2 launch` so this
# only swaps in for the default camera-launch command: the devel image's CMD is
# `bash` (and `just run bash` / `just run <cmd>` on runtime), which falls
# through to `exec "$@"` untouched.
_camera_config="/camera_config.yaml"
if [[ -s "${_camera_config}" && "${1:-}" == "ros2" && "${2:-}" == "launch" ]]; then
  printf 'Launching RealSense camera with active config: %s\n' "${_camera_config}"
  exec ros2 launch realsense2_camera rs_launch.py \
    config_file:="${_camera_config}" \
    initial_reset:=true
fi

exec "${@}"
