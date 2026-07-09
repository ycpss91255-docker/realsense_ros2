#!/usr/bin/env bash
set -euo pipefail

# ---------------------------- camera config ----------------------------
#
# Optional camera config (modeled on ros1_bridge's /bridge.yaml). The Dockerfile
# COPYs the root `camera.yaml` symlink's target to /camera_config.yaml; the
# default target is config/realsense/custom/none.yaml, an EMPTY file, so the
# stock upstream default runs unchanged. When a non-empty profile is active
# (repoint the symlink or pass --build-arg CAMERA_CONFIG=...), launch the camera
# with it via rs_launch.py's config_file arg.
CAMERA_CONFIG_FILE="/camera_config.yaml"

# Resolve the final argv into the CONFIGURED_ARGV global array without
# executing. When the command is `ros2 launch` AND a NON-empty
# /camera_config.yaml is baked in, swap in the generic rs_launch.py driven by
# that profile (config_file:= + initial_reset:=true). Any other case -- an empty
# config (the default), or a non-launch command such as the devel `bash` (and
# `just run bash` / `just run <cmd>` on runtime) -- leaves the argv untouched,
# so default behaviour is byte-identical to before. Guarded on `ros2 launch` so
# this only swaps in for the default camera-launch command.
_apply_camera_config() {
  CONFIGURED_ARGV=("$@")

  [[ "${1:-}" == "ros2" && "${2:-}" == "launch" ]] || return 0
  [[ -s "${CAMERA_CONFIG_FILE}" ]] || return 0

  printf 'Launching RealSense camera with active config: %s\n' "${CAMERA_CONFIG_FILE}"
  CONFIGURED_ARGV=(ros2 launch realsense2_camera rs_launch.py \
    "config_file:=${CAMERA_CONFIG_FILE}" initial_reset:=true)
}

main() {
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

  # Apply the baked-in camera profile (if any), then exec the resolved argv.
  _apply_camera_config "$@"
  exec "${CONFIGURED_ARGV[@]}"
}

# Only when executed as the entrypoint (not when a test sources this file):
# source ROS and exec the resolved command.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
