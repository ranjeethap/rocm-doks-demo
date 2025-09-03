#!/usr/bin/env bash
set -euo pipefail
req(){ for c in "$@"; do command -v "$c" >/dev/null || { echo "Missing: $c"; exit 1; }; done; }
req doctl docker trivy kubectl

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a; [[ -f "$ROOT/.env" ]] && . "$ROOT/.env"; set +a

REG="${REGISTRY_HOST:-registry.digitalocean.com/dokr-saas}"
TAG="${1:-dev}"
IMAGE="${REG}/matmul:${TAG}"

echo "==> DOCR login"
doctl registry login

echo "==> Build & push $IMAGE"
docker buildx build -t "$IMAGE" --platform linux/amd64 -f app/Dockerfile app --push

echo "==> Trivy scan (fail on HIGH/CRITICAL)"
trivy image --exit-code 1 --severity HIGH,CRITICAL "$IMAGE"

if [[ "$TAG" == "dev" ]]; then
  echo "==> Argo refresh (dev)"
  kubectl -n argocd annotate app rocm-matmul-dev argocd.argoproj.io/refresh=hard --overwrite || true
fi
echo "✅ $IMAGE"

