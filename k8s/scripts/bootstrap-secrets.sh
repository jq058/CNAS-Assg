#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

required_variables=(DB_USER DB_PASSWORD MYSQL_ROOT_PASSWORD REDIS_PASSWORD)
for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Required environment variable is empty: ${variable_name}" >&2
    exit 1
  fi
  case "${!variable_name}" in
    *$'\r'*|*$'\n'*)
      echo "${variable_name} must not contain a newline." >&2
      exit 1
      ;;
  esac
done

kubectl apply -f "${REPO_ROOT}/k8s/00-namespace.yaml"

secret_file="$(mktemp)"
trap 'rm -f "${secret_file}"' EXIT
chmod 600 "${secret_file}"
{
  printf 'DB_USER=%s\n' "${DB_USER}"
  printf 'DB_PASSWORD=%s\n' "${DB_PASSWORD}"
  printf 'MYSQL_ROOT_PASSWORD=%s\n' "${MYSQL_ROOT_PASSWORD}"
  printf 'REDIS_PASSWORD=%s\n' "${REDIS_PASSWORD}"
} > "${secret_file}"

kubectl -n cnas create secret generic cnas-secret \
  --from-env-file="${secret_file}" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Secret cnas/cnas-secret configured without writing credentials into the repository."
