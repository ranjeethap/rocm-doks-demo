#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/lib.sh"

ns_exists kube-system || kubectl create ns kube-system
ns_exists monitoring || kubectl create ns monitoring
ns_exists ingress-nginx || kubectl create ns ingress-nginx
ns_exists dev || kubectl create ns dev

add_or_update_repo() {
  local name="$1" url="$2"
  if helm repo list | awk '{print $1}' | grep -qx "$name"; then
    helm repo add "$name" "$url" --force-update >/dev/null 2>&1 || true
  else
    retry 5 helm repo add "$name" "$url"
  fi
}

add_or_update_repo prometheus-community https://prometheus-community.github.io/helm-charts
add_or_update_repo kubecost              https://kubecost.github.io/cost-analyzer/
add_or_update_repo sealed-secrets        https://bitnami-labs.github.io/sealed-secrets
add_or_update_repo amd-gpu-helm          https://rocm.github.io/k8s-device-plugin/
add_or_update_repo kedacore              https://kedacore.github.io/charts

helm repo update

helm repo update

# Ingress NGINX
retry 3 helm upgrade --install ingress-nginx prometheus-community/prometheus-nginx-exporter \
  --namespace ingress-nginx --wait || true # exporter only; controller usually preinstalled in DOKS apps

# kube-prometheus-stack (Prometheus, Alertmanager, Grafana)
retry 3 helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --wait --values "${ROOT}/k8s/kube-prometheus-values.yaml"

# Prometheus Adapter for Custom Metrics API
retry 3 helm upgrade --install prometheus-adapter prometheus-community/prometheus-adapter \
  --namespace monitoring --wait --values "${ROOT}/k8s/prometheus-adapter-values.yaml"

# Sealed Secrets
retry 3 helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system --wait

# Kubecost (uses Prometheus from kube-prometheus-stack)
retry 3 helm upgrade --install kubecost kubecost/cost-analyzer \
  --namespace monitoring --wait --values "${ROOT}/k8s/kubecost-values.yaml"

# AMD GPU device plugin (only if ENABLE_GPU=true)
if [[ "${ENABLE_GPU:-false}" == "true" ]]; then
  retry 3 helm upgrade --install amd-gpu amd-gpu-helm/amd-gpu \
    --namespace kube-system --wait
fi

echo "✅ Addons installed."
