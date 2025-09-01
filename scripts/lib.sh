#!/usr/bin/env bash
set -euo pipefail

load_dotenv() {
  local env_file="${1:-.env}"
  if [[ -f "$env_file" ]]; then
    set -a
    . "$env_file"
    set +a
  fi
}

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { echo "Missing command: $c"; exit 1; }
  done
}

require_env() {
  local var="$1"; local msg="${2:-}"
  # Try loading .env once if missing
  if [[ -z "${!var-}" ]]; then
    load_dotenv "${ROOT:-.}/.env"
  fi
  [[ -n "${!var-}" ]] || { echo "Missing env: $var. $msg"; exit 1; }
}

ns_exists() {
  kubectl get ns "$1" >/dev/null 2>&1
}

retry() {
  local n="${1}"; shift
  for ((i=1;i<=n;i++)); do
    "$@" && return 0 || { echo "Retry $i/$n failed: $*"; sleep $((2*i)); }
  done
  return 1
}

