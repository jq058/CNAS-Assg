#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
KIND_NODE_IMAGE="kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5"
MINIMUM_KIND_VERSION="0.32.0"

command -v kind >/dev/null 2>&1 || { echo "Required command is missing: kind" >&2; exit 1; }

kind_version_output="$(kind version)"
if [[ ! "${kind_version_output}" =~ v([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  echo "Unable to determine the installed Kind version from: ${kind_version_output}" >&2
  exit 1
fi

installed_kind_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
IFS=. read -r installed_major installed_minor installed_patch <<<"${installed_kind_version}"
IFS=. read -r minimum_major minimum_minor minimum_patch <<<"${MINIMUM_KIND_VERSION}"
if (( installed_major < minimum_major \
   || (installed_major == minimum_major && installed_minor < minimum_minor) \
   || (installed_major == minimum_major && installed_minor == minimum_minor && installed_patch < minimum_patch) )); then
  echo "Kind v${MINIMUM_KIND_VERSION} or newer is required; found v${installed_kind_version}." >&2
  exit 1
fi

if ! kind get clusters | grep -Fxq cnas-cluster; then
  kind create cluster \
    --config "${REPO_ROOT}/kind-cluster.yaml" \
    --image "${KIND_NODE_IMAGE}"
else
  echo "Using existing cnas-cluster; no cluster was deleted or recreated."
  kubectl config use-context kind-cnas-cluster >/dev/null
fi

bash "${SCRIPT_DIR}/install-platform.sh"
