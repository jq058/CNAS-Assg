#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

for command_name in kubectl openssl; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Required command is missing: ${command_name}" >&2
    exit 1
  }
done

kubectl apply -f "${REPO_ROOT}/k8s/00-namespace.yaml"

certificate_directory="$(mktemp -d)"
cleanup_certificate_directory() {
  rm -f -- "${certificate_directory}/tls.key" "${certificate_directory}/tls.crt"
  rmdir -- "${certificate_directory}" 2>/dev/null || true
}
trap cleanup_certificate_directory EXIT

openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
  -days 30 \
  -keyout "${certificate_directory}/tls.key" \
  -out "${certificate_directory}/tls.crt" \
  -subj "/CN=cnas.local" \
  -addext "subjectAltName=DNS:cnas.local"

kubectl -n cnas create secret tls cnas-local-tls \
  --cert="${certificate_directory}/tls.crt" \
  --key="${certificate_directory}/tls.key" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Local self-signed TLS Secret created. Use a trusted issuer outside the coursework Kind cluster."
