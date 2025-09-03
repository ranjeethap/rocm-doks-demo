#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"

# load .env
if [[ -f "${ROOT}/.env" ]]; then set -a; . "${ROOT}/.env"; set +a; fi

DO_REGION="${DO_REGION:-nyc1}"
DO_PROJECT_NAME="${DO_PROJECT_NAME:-rocm-doks-demo}"
K8S_VERSION="${K8S_VERSION:-1.31.9-do.3}"

INSTALL_ARGOCD="${INSTALL_ARGOCD:-true}"
INSTALL_SEALED="${INSTALL_SEALED:-true}"
INSTALL_METRICS="${INSTALL_METRICS:-true}"

req() { for c in "$@"; do command -v "$c" >/dev/null || { echo "Missing: $c"; exit 1; }; done; }
req doctl kubectl terraform helm

[[ -n "${DO_TOKEN:-}" ]] || { echo "Missing DO_TOKEN in env/.env"; exit 1; }
export DIGITALOCEAN_TOKEN="$DO_TOKEN"

retry() { local n="$1"; shift; local i=1; until "$@"; do ((i>=n))&&return 1; echo "Retry $i/$n failed: $*"; sleep $((2*i)); ((i++)); done; }

wait_for_argocd_crds() {
  kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=180s
  kubectl wait --for=condition=Established crd/appprojects.argoproj.io --timeout=180s
}

apply_argocd_apps() {
  # ensure kube creds are fresh before touching CRDs
  ensure_kube
  wait_for_argocd_crds
  # apply your GitOps apps idempotently
  kubectl apply -f k8s/argocd/app-dev.yaml
  kubectl apply -f k8s/argocd/app-prod.yaml
  # ask Argo to reconcile immediately
  kubectl -n argocd annotate app rocm-matmul-dev  argocd.argoproj.io/refresh=hard --overwrite || true
  kubectl -n argocd annotate app rocm-matmul-prod argocd.argoproj.io/refresh=hard --overwrite || true
}

ensure_kube() {
  retry 5 doctl kubernetes cluster kubeconfig save "${DO_PROJECT_NAME}" \
    --access-token "$DIGITALOCEAN_TOKEN" --alias "${DO_PROJECT_NAME}" --set-current-context
  kubectl version --short >/dev/null
  kubectl get nodes >/dev/null
}

add_repo() { local n="$1" u="$2"; if helm repo list | awk 'NR>1{print $1}' | grep -qx "$n"; then helm repo add "$n" "$u" --force-update >/dev/null 2>&1 || true; else retry 5 helm repo add "$n" "$u"; fi; }
helm_install_wait() { # rel chart ns [args...]
  local rel="$1" chart="$2" ns="$3"; shift 3
  kubectl create ns "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true
  retry 3 helm upgrade --install "$rel" "$chart" -n "$ns" --timeout 10m --wait --atomic "$@"
}

install_argocd() {
  add_repo argo https://argoproj.github.io/argo-helm; helm repo update
  ensure_kube
  helm_install_wait argocd argo/argo-cd argocd
  echo "ArgoCD admin password:"; kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d || true; echo
}

install_sealed() {
  add_repo sealed-secrets https://bitnami-labs.github.io/sealed-secrets; helm repo update
  ensure_kube
  helm_install_wait sealed-secrets sealed-secrets/sealed-secrets kube-system
}

install_metrics() {
  add_repo ingress-nginx https://kubernetes.github.io/ingress-nginx
  add_repo prometheus-community https://prometheus-community.github.io/helm-charts
  add_repo kedacore https://kedacore.github.io/charts
  add_repo metrics-server https://kubernetes-sigs.github.io/metrics-server/
  helm repo update

  # ingress controller (LB + metrics)
  helm_install_wait ingress-nginx ingress-nginx/ingress-nginx ingress-nginx \
    --set controller.metrics.enabled=true --set controller.service.type=LoadBalancer

  # kube-prometheus-stack (Grafana/Prom/Alertmanager); expose via LB if requested
  if [[ "${EXPOSE_MONITORING_LB:-false}" == "true" ]]; then
    helm_install_wait kube-prometheus-stack prometheus-community/kube-prometheus-stack monitoring \
      --set grafana.service.type=LoadBalancer \
      --set prometheus.service.type=LoadBalancer \
      --set alertmanager.service.type=LoadBalancer
  else
    helm_install_wait kube-prometheus-stack prometheus-community/kube-prometheus-stack monitoring
  fi

  # metrics-server (proper args array)
  helm_install_wait metrics-server metrics-server/metrics-server kube-system \
    --set-string args[0]=--kubelet-insecure-tls \
    --set-string args[1]=--kubelet-preferred-address-types=InternalIP

  # KEDA
  helm_install_wait keda kedacore/keda keda
}

tf_apply() {
  export TF_VAR_do_token="$DO_TOKEN"
  terraform -chdir="$TF_DIR" init -upgrade
  terraform -chdir="$TF_DIR" apply -auto-approve \
    -var="do_token=$DO_TOKEN" -var="region=$DO_REGION" -var="cluster_name=$DO_PROJECT_NAME" -var="k8s_version=$K8S_VERSION"
}
tf_destroy() {
  export TF_VAR_do_token="$DO_TOKEN"
  terraform -chdir="$TF_DIR" init -upgrade
  terraform -chdir="$TF_DIR" destroy -auto-approve \
    -var="do_token=$DO_TOKEN" -var="region=$DO_REGION" -var="cluster_name=$DO_PROJECT_NAME" -var="k8s_version=$K8S_VERSION"
}

case "${1:-}" in
  create)
    echo "==> Creating DOKS cluster ${DO_PROJECT_NAME}…"; tf_apply
    echo "==> Kubeconfig…"; ensure_kube
    echo "==> Wiring Argo Applications (dev & prod)…"
    apply_argocd_apps
    [[ "$INSTALL_SEALED" == "true" ]]   && { echo "==> Sealed Secrets…"; install_sealed; }
    [[ "$INSTALL_ARGOCD" == "true" ]]   && { echo "==> ArgoCD…"; install_argocd; }
    [[ "$INSTALL_METRICS" == "true" ]]  && { echo "==> Addons…"; install_metrics; }
    echo "✅ Cluster ready."
    ;;
  delete)
    echo "==> Destroying DOKS cluster ${DO_PROJECT_NAME}…"; tf_destroy; echo "✅ Done."
    ;;
  *)
    echo "Usage: $(basename "$0") <create|delete>"; exit 1;;
esac

