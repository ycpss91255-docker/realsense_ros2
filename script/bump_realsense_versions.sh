#!/usr/bin/env bash
#
# Bump the pinned RealSense source versions in the Dockerfile.
#
# realsense-ros is the driver: query its latest release, read the librealsense
# minor it declares (find_package(realsense2 X.Y.Z) in realsense2_camera/
# CMakeLists.txt), and pin librealsense to the newest release tag in THAT minor.
# This never pairs a librealsense+realsense-ros combo upstream did not test.
# Rewrites the two ARG default lines in place, prints each old->new transition to
# stdout, and emits a trailing abi_safe=<bool> line for the scheduled workflow.
# Exit 0 when a change was made, 10 when already up to date. dependabot's docker
# ecosystem cannot see ARG-embedded git tags, so this custom helper drives
# .github/workflows/upstream-bump.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# Overridable so a sourcing test can point current_arg / set_arg at a fixture
# Dockerfile; unset in real use, it resolves to the repo Dockerfile as before.
DOCKERFILE="${DOCKERFILE:-${SCRIPT_DIR}/../Dockerfile}"
readonly DOCKERFILE
# Overridable so a sourcing test can point prepend_changelog_entry at a fixture.
CHANGELOG="${CHANGELOG:-${SCRIPT_DIR}/../doc/changelog/CHANGELOG.md}"
readonly CHANGELOG
readonly LIBREALSENSE_REPO="IntelRealSense/librealsense"
readonly REALSENSE_ROS_REPO="IntelRealSense/realsense-ros"

readonly EXIT_UP_TO_DATE=10

usage() {
  cat >&2 <<'EOF'
Usage: bump_realsense_versions.sh [-h|--help]

Bump the pinned RealSense source tags in the Dockerfile ARGs. realsense-ros is
the driver: its latest release picks the target, and librealsense is pinned to
the newest release in the minor realsense-ros declares (find_package(realsense2
X.Y.Z)), so the pair is always one upstream tested. Prints each old->new
transition and a trailing abi_safe=<bool> classification to stdout.

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

# Rewrites a Dockerfile ARG default in place: set_arg <ARG_NAME> <new_value>.
set_arg() {
  local arg_name="$1"
  local new_value="$2"
  sed -i -E "s|^(ARG ${arg_name}=\")[^\"]+(\")|\\1${new_value}\\2|" "${DOCKERFILE}"
}

# Fetches the latest release tag of a GitHub repo: latest_tag <owner/repo>.
latest_tag() {
  local repo="$1"
  gh api "repos/${repo}/releases/latest" --jq '.tag_name'
}

# Lists every release tag of a repo, newline-separated: list_release_tags <repo>.
list_release_tags() {
  local repo="$1"
  gh api "repos/${repo}/releases" --paginate --jq '.[].tag_name'
}

# Fetches a realsense-ros tag's realsense2_camera/CMakeLists.txt (decoded):
# fetch_ros_cmakelists <tag>.
fetch_ros_cmakelists() {
  local tag="$1"
  gh api "repos/${REALSENSE_ROS_REPO}/contents/realsense2_camera/CMakeLists.txt?ref=${tag}" \
    --jq '.content' | base64 -d
}

# Parses the librealsense minor realsense-ros requires from its CMakeLists text:
# required_librealsense_minor <cmake_text> -> e.g. 2.58.
required_librealsense_minor() {
  local cmake_text="$1"
  printf '%s' "${cmake_text}" \
    | grep -oP 'find_package\(\s*realsense2\s+\K[0-9]+\.[0-9]+' \
    | head -1
}

# Parses the full librealsense version realsense-ros declares (the floor):
# required_librealsense_version <cmake_text> -> e.g. 2.58.0.
required_librealsense_version() {
  local cmake_text="$1"
  printf '%s' "${cmake_text}" \
    | grep -oP 'find_package\(\s*realsense2\s+\K[0-9]+\.[0-9]+\.[0-9]+' \
    | head -1
}

# Picks the highest release tag in a given major.minor from a newline-separated
# tag list, ignoring other minors: latest_tag_in_minor <tags> <minor>.
latest_tag_in_minor() {
  local tags="$1"
  local minor="$2"
  local escaped="${minor//./\\.}"
  printf '%s\n' "${tags}" \
    | grep -E "^v?${escaped}\.[0-9]+$" \
    | sort -V \
    | tail -1
}

# Classifies a bump by major.minor: same major.minor is a same-minor drop-in
# (exit 0), a minor/major change is not (exit 1). Keyed on the realsense-ros
# tags, since a realsense-ros minor change is what pulls librealsense into a new
# minor. same_minor_bump <old_tag> <new_tag>.
same_minor_bump() {
  local old_tag="$1"
  local new_tag="$2"
  local old_mm new_mm
  old_mm="$(printf '%s' "${old_tag}" | sed -E 's/^v?([0-9]+)\.([0-9]+).*/\1.\2/')"
  new_mm="$(printf '%s' "${new_tag}" | sed -E 's/^v?([0-9]+)\.([0-9]+).*/\1.\2/')"
  [[ "${old_mm}" == "${new_mm}" ]]
}

# Prepends a bullet under [Unreleased] > ### Changed, creating the ### Changed
# subheading if the Unreleased section lacks one: prepend_changelog_entry <text>.
prepend_changelog_entry() {
  local entry="$1"
  local tmp
  tmp="$(mktemp)"
  awk -v bullet="- ${entry}" '
    /^## / {
      # Leaving the Unreleased section without a ### Changed: create one here.
      if (in_unrel && !done) {
        print "### Changed"
        print bullet
        print ""
        done = 1
      }
      in_unrel = ($0 ~ /^## \[Unreleased\]/)
      print
      next
    }
    in_unrel && !done && /^### Changed/ {
      print
      print bullet
      done = 1
      next
    }
    { print }
    END {
      if (in_unrel && !done) {
        print "### Changed"
        print bullet
      }
    }
  ' "${CHANGELOG}" > "${tmp}"
  mv "${tmp}" "${CHANGELOG}"
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

  local cur_lib cur_ros
  cur_lib="$(current_arg LIBREALSENSE_VERSION || true)"
  cur_ros="$(current_arg REALSENSE_ROS_VERSION || true)"
  if [[ -z "${cur_lib}" || -z "${cur_ros}" ]]; then
    echo "bump_realsense_versions.sh: could not parse ARGs from ${DOCKERFILE}" >&2
    return 1
  fi

  # realsense-ros drives the pairing.
  local new_ros
  new_ros="$(latest_tag "${REALSENSE_ROS_REPO}" || true)"
  if [[ -z "${new_ros}" ]]; then
    echo "bump_realsense_versions.sh: could not fetch latest realsense-ros tag" >&2
    return 1
  fi

  # Read the librealsense minor realsense-ros declares at that tag.
  local cmake_text required_minor declared_full
  cmake_text="$(fetch_ros_cmakelists "${new_ros}" || true)"
  required_minor="$(required_librealsense_minor "${cmake_text}")"
  declared_full="$(required_librealsense_version "${cmake_text}")"
  if [[ -z "${required_minor}" || -z "${declared_full}" ]]; then
    echo "bump_realsense_versions.sh: could not read find_package(realsense2 ...) from realsense-ros ${new_ros}" >&2
    return 1
  fi

  # Pin librealsense to the newest release in that minor, floored at the declared
  # version -- never below it and never into a minor realsense-ros did not declare.
  local lib_tags new_lib
  lib_tags="$(list_release_tags "${LIBREALSENSE_REPO}" || true)"
  new_lib="$(latest_tag_in_minor "${lib_tags}" "${required_minor}")"
  if [[ -z "${new_lib}" ]] \
    || [[ "$(printf '%s\nv%s\n' "${new_lib}" "${declared_full}" | sort -V | tail -1)" != "${new_lib}" ]]; then
    new_lib="v${declared_full}"
  fi

  local changed=0
  if [[ "${new_lib}" != "${cur_lib}" ]]; then
    set_arg LIBREALSENSE_VERSION "${new_lib}"
    echo "LIBREALSENSE_VERSION: ${cur_lib} -> ${new_lib}"
    changed=1
  fi
  if [[ "${new_ros}" != "${cur_ros}" ]]; then
    set_arg REALSENSE_ROS_VERSION "${new_ros}"
    echo "REALSENSE_ROS_VERSION: ${cur_ros} -> ${new_ros}"
    changed=1
  fi

  if [[ "${changed}" -eq 0 ]]; then
    echo "bump_realsense_versions.sh: already up to date"
    return "${EXIT_UP_TO_DATE}"
  fi

  # Auto-merge gate keys on realsense-ros: a realsense-ros PATCH (same declared
  # minor, find_package minor unchanged) is a safe drop-in; a minor/major change
  # pulls librealsense into a new minor and needs human review.
  local abi_safe="true"
  if ! same_minor_bump "${cur_ros}" "${new_ros}"; then
    abi_safe="false"
  fi

  # Compose + prepend a single [Unreleased] > ### Changed CHANGELOG bullet.
  local entry
  entry="Bumped pinned RealSense sources: realsense-ros ${cur_ros} -> ${new_ros}, librealsense ${cur_lib} -> ${new_lib} (realsense-ros declares realsense2 ${required_minor})"
  prepend_changelog_entry "${entry}"

  # Machine-readable classification for the workflow (last stdout line).
  echo "abi_safe=${abi_safe}"
  return 0
}

# Run main only when executed directly, so tests can source this file and
# exercise the pure helpers without hitting the network.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "${@}"
fi
