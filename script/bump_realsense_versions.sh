#!/usr/bin/env bash
#
# Bump the pinned RealSense source versions in the Dockerfile.
#
# Reads the current LIBREALSENSE_VERSION / REALSENSE_ROS_VERSION from the
# Dockerfile ARGs, queries the latest upstream GitHub releases, and, when a
# newer tag exists, rewrites the two ARG default lines in place. Prints each
# old->new transition to stdout for the scheduled workflow to build a PR
# branch/body. Exit 0 when a change was made, 10 when already up to date.
# dependabot's docker ecosystem cannot see ARG-embedded git tags, so this
# custom helper drives .github/workflows/upstream-bump.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DOCKERFILE="${SCRIPT_DIR}/../Dockerfile"
readonly LIBREALSENSE_REPO="IntelRealSense/librealsense"
readonly REALSENSE_ROS_REPO="IntelRealSense/realsense-ros"

readonly EXIT_UP_TO_DATE=10

usage() {
  cat >&2 <<'EOF'
Usage: bump_realsense_versions.sh [-h|--help]

Query the latest IntelRealSense/librealsense and IntelRealSense/realsense-ros
releases and, when newer than the tags pinned in the Dockerfile ARGs
(LIBREALSENSE_VERSION / REALSENSE_ROS_VERSION), rewrite those two ARG default
lines in place. Prints each old->new transition to stdout.

Requires the `gh` CLI authenticated (GH_TOKEN in CI). Exit codes:
  0    Dockerfile was updated (at least one bump).
  10   Already up to date (no change).
  1    Error.

Options:
  -h, --help   Show this help and exit.
EOF
}

# Reads the value of a Dockerfile ARG default: current_arg <ARG_NAME>.
current_arg() {
  local arg_name="$1"
  grep -oP "ARG ${arg_name}=\"\\K[^\"]+" "${DOCKERFILE}"
}

# Fetches the latest release tag of a GitHub repo: latest_tag <owner/repo>.
latest_tag() {
  local repo="$1"
  gh api "repos/${repo}/releases/latest" --jq '.tag_name'
}

# Rewrites a Dockerfile ARG default in place: set_arg <ARG_NAME> <new_value>.
set_arg() {
  local arg_name="$1"
  local new_value="$2"
  sed -i -E "s|^(ARG ${arg_name}=\")[^\"]+(\")|\\1${new_value}\\2|" "${DOCKERFILE}"
}

main() {
  case "${1:-}" in
    -h | --help)
      usage
      return 0
      ;;
    "") ;;
    *)
      echo "bump_realsense_versions.sh: unknown argument '${1}'" >&2
      usage
      return 1
      ;;
  esac

  local changed=0
  local arg repo cur new
  for pair in \
    "LIBREALSENSE_VERSION ${LIBREALSENSE_REPO}" \
    "REALSENSE_ROS_VERSION ${REALSENSE_ROS_REPO}"; do
    arg="${pair%% *}"
    repo="${pair##* }"

    cur="$(current_arg "${arg}" || true)"
    if [[ -z "${cur}" ]]; then
      echo "bump_realsense_versions.sh: could not parse ${arg} from ${DOCKERFILE}" >&2
      return 1
    fi

    new="$(latest_tag "${repo}" || true)"
    if [[ -z "${new}" ]]; then
      echo "bump_realsense_versions.sh: could not fetch latest tag for ${repo}" >&2
      return 1
    fi

    if [[ "${new}" != "${cur}" ]]; then
      set_arg "${arg}" "${new}"
      echo "${arg}: ${cur} -> ${new}"
      changed=1
    fi
  done

  if [[ "${changed}" -eq 0 ]]; then
    echo "bump_realsense_versions.sh: already up to date"
    return "${EXIT_UP_TO_DATE}"
  fi

  return 0
}

main "${@}"
