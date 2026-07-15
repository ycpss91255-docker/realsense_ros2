#!/usr/bin/env bash
#
# pre-build hook (base #440): host-side, runs before build.sh main logic.
# Receives the same "$@" as build.sh. Non-zero exit aborts the wrapper.
# Skipped when ./build.sh runs with --dry-run.
#
# Purpose: mirror build.sh's `test-tools:local` auto-build for the librealsense
# SDK. The main Dockerfile FROMs `${LIBREALSENSE_IMAGE}` (default the version-
# scoped `librealsense:${LIBREALSENSE_VERSION}-${UBUNTU_CODENAME}`) and COPYs the
# prebuilt librealsense trees out of it. In CI, main.yaml passes
# LIBREALSENSE_IMAGE=ghcr.io/.../librealsense:<ver>-<codename>
# so buildx PULLS the prebuilt SDK. For a LOCAL `just build` / `./build.sh`
# (LIBREALSENSE_IMAGE unset) there is no such image, so this hook builds it from
# docker/Dockerfile.librealsense first -> the local build is self-contained and
# needs no GHCR access.
#
# Contract:
#   - LIBREALSENSE_IMAGE already set (caller/CI provides it) -> no-op, exit 0.
#   - otherwise -> docker build -t librealsense:<version>-<codename> from the SDK.
#
# UBUNTU_CODENAME / LIBREALSENSE_VERSION default to the main Dockerfile's pins:
# this hook READS them from the Dockerfile ARGs (the single source of truth) so a
# version bump that seds only the Dockerfile propagates here with no 3-way drift.
# Still env-overridable so a non-jammy local build (e.g. UBUNTU_CODENAME=noble
# ./build.sh, for jazzy) provisions the matching SDK. The SDK is keyed on the
# Ubuntu codename, not the ROS distro: librealsense2 is ROS-agnostic and its .so
# is ABI-bound to the Ubuntu release.

set -euo pipefail

# Reads a Dockerfile ARG default value: dockerfile_arg <file> <ARG_NAME>.
dockerfile_arg() {
  local dockerfile="$1"
  local arg_name="$2"
  grep -oP "ARG ${arg_name}=\"\\K[^\"]+" "${dockerfile}"
}

main() {
  # If the caller/CI already provides the SDK image, do nothing.
  if [[ -n "${LIBREALSENSE_IMAGE:-}" ]]; then
    return 0
  fi

  # Resolve the repo root from this hook's own location (script/hooks/pre/),
  # so the docker build works from any CWD.
  local hook_dir repo_root main_dockerfile sdk_context sdk_dockerfile
  hook_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  repo_root="$(cd -- "${hook_dir}/../../.." && pwd -P)"
  main_dockerfile="${repo_root}/Dockerfile"
  sdk_context="${repo_root}/docker"
  sdk_dockerfile="${sdk_context}/Dockerfile.librealsense"

  # Pins default to the main Dockerfile's global ARGs (single source of truth);
  # env-overridable.
  local ubuntu_codename librealsense_version
  ubuntu_codename="${UBUNTU_CODENAME:-$(dockerfile_arg "${main_dockerfile}" UBUNTU_CODENAME)}"
  librealsense_version="${LIBREALSENSE_VERSION:-$(dockerfile_arg "${main_dockerfile}" LIBREALSENSE_VERSION)}"

  if [[ ! -f "${sdk_dockerfile}" ]]; then
    printf '[pre-build] ERROR: SDK Dockerfile not found: %s\n' \
      "${sdk_dockerfile}" >&2
    return 1
  fi

  printf '[pre-build] building librealsense:%s-%s\n' \
    "${librealsense_version}" "${ubuntu_codename}" >&2

  docker build \
    -t "librealsense:${librealsense_version}-${ubuntu_codename}" \
    --build-arg "UBUNTU_CODENAME=${ubuntu_codename}" \
    --build-arg "LIBREALSENSE_VERSION=${librealsense_version}" \
    -f "${sdk_dockerfile}" \
    "${sdk_context}"
}

main "$@"
