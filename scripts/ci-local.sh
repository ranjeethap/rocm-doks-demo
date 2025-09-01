#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/lib.sh"

require_cmd docker trivy kubectl helm
ns_exists dev || kubectl create ns dev

IMAGE="${DOCR_REPO:-registry.digitalocean.com/rocm-gpu-demo/matmul}:${TAG:-v0.1.$(date +%s)}"

echo "Building multi-arch image with buildx (CPU-only fallback works everywhere; ROCm libs present for GPU nodes)..."
docker buildx create --use >/dev/null 2>&1 || true
docker buildx build --platform linux/amd64 -t "$IMAGE" -f "${ROOT}/app/Dockerfile" "${ROOT}/app" --push

echo "Scanning image with Trivy (fail on HIGH/CRITICAL)..."
trivy image --exit-code 1 --severity HIGH,CRITICAL "$IMAGE" || { echo "Trivy found HIGH/CRITICAL issues"; exit 1; }

echo "Templating manifests with image tag..."
yq e ".spec.template.spec.containers[0].image = \"$IMAGE\"" "${ROOT}/k8s/deployment.yaml" | kubectl apply -f -

kubectl apply -f "${ROOT}/k8s/service.yaml"
kubectl apply -f "${ROOT}/k8s/ingress.yaml" || true
kubectl apply -f "${ROOT}/k8s/hpa.yaml"

echo "If you need DOCR pull secret in cluster:"
echo "  kubectl -n dev create secret docker-registry docr --docker-server=$(echo $IMAGE | cut -d/ -f1,2) --docker-username=$(doctl registry docker-config-json --expiry-seconds 3600 | jq -r '.auths | to_entries[0].value.username') --docker-password=$(doctl registry docker-config-json --expiry-seconds 3600 | jq -r '.auths | to_entries[0].value.password')"
echo "Then seal it with kubeseal and apply to dev namespace."
