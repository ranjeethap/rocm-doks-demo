#!/usr/bin/env bash
set -euo pipefail

# promote.sh — retag/push DOCR image and flip prod overlay tag, then sync Argo
# Usage:
#   ./scripts/promote.sh v1.0.0           # promotes from :dev to :v1.0.0
#   ./scripts/promote.sh v1.0.1 --from dev
#
# Requires: doctl (logged into correct context), docker buildx

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <NEW_TAG> [--from <FROM_TAG:default=dev>]"
  exit 1
fi

NEW_TAG="$1"; shift
FROM_TAG="dev"
if [[ "${1:-}" == "--from" ]]; then
  FROM_TAG="${2:-dev}"
fi

# Load .env if present
if [[ -f .env ]]; then
  # shellcheck disable=SC1090
  source .env
fi

REGISTRY_NAME="${REGISTRY_NAME:-dokr-saas}"
IMAGE_NAME="${IMAGE_NAME:-matmul}"

# Resolve DOCR endpoint (Endpoint column)
SERVER="$(doctl registry get "${REGISTRY_NAME}" --format Endpoint --no-header 2>/dev/null | tr -d '[:space:]' || true)"
if [[ -z "$SERVER" || "$SERVER" == "<nil>" ]]; then
  SERVER="registry.digitalocean.com/${REGISTRY_NAME}"
fi

SRC_REF="${SERVER}/${IMAGE_NAME}:${FROM_TAG}"
DST_REF="${SERVER}/${IMAGE_NAME}:${NEW_TAG}"

echo "➡️  Promoting ${SRC_REF}  →  ${DST_REF}"

# Ensure buildx exists
if docker buildx inspect doks >/dev/null 2>&1; then
  docker buildx use doks
else
  docker buildx create --name doks --driver docker-container --use
fi

# Login to DOCR
doctl registry login

# Try registry-side retag (no pull). Fallback to pull/tag/push if imagetools fails.
if docker buildx imagetools create -t "${DST_REF}" "${SRC_REF}"; then
  echo "✅ Created registry tag ${DST_REF} from ${SRC_REF}"
else
  echo "ℹ️  imagetools failed; falling back to pull/tag/push…"
  docker pull "${SRC_REF}"
  docker tag  "${SRC_REF}" "${DST_REF}"
  docker push "${DST_REF}"
fi

# Update prod overlay image tag
KUST="k8s/overlays/prod/kustomization.yaml"
if [[ ! -f "$KUST" ]]; then
  echo "❌ ${KUST} not found"
  exit 1
fi

# portable sed (macOS/BSD)
sed -E -i.bak "s|(newTag:\s*).*$|\1${NEW_TAG}|" "$KUST"
rm -f "${KUST}.bak"

# Validate kustomize renders
kubectl kustomize k8s/overlays/prod >/dev/null && echo "✅ prod kustomize OK"

# Commit & push overlay change
git add "$KUST"
git commit -m "Promote ${IMAGE_NAME}:${FROM_TAG} -> ${NEW_TAG} (prod overlay)"
git push

# Kick Argo to re-sync prod
kubectl -n argocd annotate app rocm-matmul-prod argocd.argoproj.io/refresh=hard --overwrite

echo "🎉 Promotion complete."
echo "   Image: ${DST_REF}"

