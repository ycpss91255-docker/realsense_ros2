#!/usr/bin/env bash
#
# Check the vendored RealSense udev rules against upstream at the pinned SDK tag.
#
# config/realsense/99-realsense-libusb.rules is vendored from
# IntelRealSense/librealsense at the tag in the Dockerfile ARG
# LIBREALSENSE_VERSION. This script parses that tag, fetches the upstream
# config/99-realsense-libusb.rules at that tag, and diffs it against the
# committed copy. Exit 0 when identical; non-zero (printing the unified diff)
# on drift. Used locally and by .github/workflows/upstream-bump.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly REPO_ROOT="${SCRIPT_DIR}/.."
readonly DOCKERFILE="${REPO_ROOT}/Dockerfile"
readonly RULES_LOCAL="${REPO_ROOT}/config/realsense/99-realsense-libusb.rules"
readonly UPSTREAM_PATH="config/99-realsense-libusb.rules"

usage() {
  cat >&2 <<'EOF'
Usage: check_udev_rules_sync.sh [-h|--help]

Diff the vendored config/realsense/99-realsense-libusb.rules against the
upstream IntelRealSense/librealsense file at the SDK tag pinned in the
Dockerfile ARG LIBREALSENSE_VERSION.

Exits 0 when the vendored copy matches upstream, non-zero (printing the unified
diff) when they have drifted. Run it locally or from the scheduled
upstream-bump workflow to catch a stale udev-rules vendor.

Options:
  -h, --help   Show this help and exit.
EOF
}

main() {
  case "${1:-}" in
    -h | --help)
      usage
      return 0
      ;;
    "") ;;
    *)
      echo "check_udev_rules_sync.sh: unknown argument '${1}'" >&2
      usage
      return 1
      ;;
  esac

  if [[ ! -f "${RULES_LOCAL}" ]]; then
    echo "check_udev_rules_sync.sh: vendored rules not found: ${RULES_LOCAL}" >&2
    return 1
  fi

  local pinned_tag
  pinned_tag="$(grep -oP 'ARG LIBREALSENSE_VERSION="\K[^"]+' "${DOCKERFILE}" || true)"
  if [[ -z "${pinned_tag}" ]]; then
    echo "check_udev_rules_sync.sh: could not parse LIBREALSENSE_VERSION from ${DOCKERFILE}" >&2
    return 1
  fi

  local upstream_url
  upstream_url="https://raw.githubusercontent.com/IntelRealSense/librealsense/${pinned_tag}/${UPSTREAM_PATH}"

  local upstream_file vendored_body
  upstream_file="$(mktemp)"
  vendored_body="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${upstream_file}' '${vendored_body}'" EXIT

  if ! curl -fsSL "${upstream_url}" -o "${upstream_file}"; then
    echo "check_udev_rules_sync.sh: failed to fetch ${upstream_url}" >&2
    return 1
  fi

  # The vendored copy carries a local provenance header above upstream's
  # leading `##Version=...##` marker; strip it so only the upstream-derived
  # body is compared.
  sed -n '/^##Version/,$p' "${RULES_LOCAL}" > "${vendored_body}"

  if diff -u "${upstream_file}" "${vendored_body}" \
      --label "upstream@${pinned_tag}" --label "vendored"; then
    echo "check_udev_rules_sync.sh: udev rules in sync with librealsense ${pinned_tag}"
    return 0
  fi

  echo "check_udev_rules_sync.sh: DRIFT -- vendored udev rules differ from librealsense ${pinned_tag}" >&2
  return 1
}

main "${@}"
