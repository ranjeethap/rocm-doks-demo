#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/lib.sh"

# --- auto-install helpers ---
add_or_update_repo() {
  local name="$1" url="$2"
  if helm repo list | awk 'NR>1{print $1}' | grep -qx "$name"; then
    helm repo add "$name" "$url" --force-update >/dev/null 2>&1 || true
  else
    retry 5 helm repo add "$name" "$url"
  fi
}

install_argocd() {
  add_or_update_repo argo https://argoproj.github.io/argo-helm
  helm repo update
  retry 3 helm upgrade --install argocd argo/argo-cd \
    --namespace argocd --create-namespace --wait

  # Optionally expose via LoadBalancer (set ARGOCD_EXPOSE_LB=true in .env)
  if [[ "${ARGOCD_EXPOSE_LB:-false}" == "true" ]]; then
    kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"LoadBalancer"}}' || true
  fi

  echo "🎯 ArgoCD installed."
  echo "Admin password:"
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
}

install_sealed_secrets() {
  add_or_update_repo sealed-secrets https://bitnami-labs.github.io/sealed-secrets
  helm repo update
  retry 3 helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
    --namespace kube-system --wait
  echo "🔐 Sealed Secrets installed."
}

# Auto-load and export variables from .env if present
ENV_FILE="${ROOT}/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a              # auto-export all variables loaded below
  . "$ENV_FILE"       # source .env
  set +a
fi


CMD="${1:-}"
case "${CMD}" in
  create)
    require_env DO_TOKEN "Set DO_TOKEN in .env and 'source .env'"
    export TF_VAR_do_token="${DO_TOKEN}"
    export TF_VAR_region="${DO_REGION:-nyc1}"
    export TF_VAR_cluster_name="${DO_PROJECT_NAME:-rocm-gpu-demo}"
    export TF_VAR_enable_gpu="${ENABLE_GPU:-false}"
    export TF_VAR_gpu_node_size="${GPU_NODE_SIZE:-gpu-mi300x1-192gb}"

    pushd "${ROOT}/terraform" >/dev/null
    terraform init -upgrade
    terraform apply -auto-approve
    popd >/dev/null

    # Save kubeconfig
    doctl kubernetes cluster kubeconfig save "${DO_PROJECT_NAME:-rocm-gpu-demo}" \
      --access-token "${DO_TOKEN}" \
      --alias "${DO_PROJECT_NAME:-rocm-gpu-demo}" \
      --set-current-context
    ;;

    # Install GitOps & secrets controllers automatically
    install_argocd
    install_sealed_secrets

    # Apply your ArgoCD Application if present
    if [[ -f "${ROOT}/argocd-app.yaml" ]]; then
      kubectl apply -f "${ROOT}/argocd-app.yaml"
      echo "✅ Applied ArgoCD Application (argocd-app.yaml)."
    fi


  nodeup)
    require_env DO_TOKEN
    CLUSTER_ID="$(doctl kubernetes cluster list --access-token "${DO_TOKEN}" --format ID,Name | awk -v n="${DO_PROJECT_NAME:-rocm-gpu-demo}" '$2==n{print $1}')"
    NP_NAME="${2:-cpu-pool}"
    COUNT="${3:-1}"
    NP_ID="$(doctl kubernetes cluster node-pool list "$CLUSTER_ID" --access-token "${DO_TOKEN}" --format ID,Name | awk -v n="$NP_NAME" '$2==n{print $1}')"
    doctl kubernetes cluster node-pool update "$CLUSTER_ID" "$NP_ID" --count "$COUNT" --access-token "${DO_TOKEN}"
    ;;

  nodedown)
    require_env DO_TOKEN
    CLUSTER_ID="$(doctl kubernetes cluster list --access-token "${DO_TOKEN}" --format ID,Name | awk -v n="${DO_PROJECT_NAME:-rocm-gpu-demo}" '$2==n{print $1}')"
    NP_NAME="${2:-cpu-pool}"
    NP_ID="$(doctl kubernetes cluster node-pool list "$CLUSTER_ID" --access-token "${DO_TOKEN}" --format ID,Name | awk -v n="$NP_NAME" '$2==n{print $1}')"
    doctl kubernetes cluster node-pool update "$CLUSTER_ID" "$NP_ID" --count 0 --access-token "${DO_TOKEN}"
    ;;

  delete)
    require_env DO_TOKEN
    pushd "${ROOT}/terraform" >/dev/null
    TF_VAR_do_token="${DO_TOKEN}" terraform destroy -auto-approve || true
    popd >/dev/null
    ;;

  *)
    cat <<EOF
Usage: $0 {create|nodeup [pool count]|nodedown [pool]|delete}
EOF
    ;;
esac
