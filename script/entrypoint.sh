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

exec "${@}"
