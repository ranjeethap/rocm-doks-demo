#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && { set -a; . "${ROOT}/.env"; set +a; }

retry(){ local n="$1";shift; local i=1; until "$@"; do ((i>=n))&&return 1; echo "Retry $i/$n failed: $*"; sleep $((2*i)); ((i++)); done; }
add_repo(){ local n="$1" u="$2"; if helm repo list|awk 'NR>1{print $1}'|grep -qx "$n"; then helm repo add "$n" "$u" --force-update >/dev/null 2>&1||true; else retry 5 helm repo add "$n" "$u"; fi; }

ensure_kube() {
  export DIGITALOCEAN_TOKEN="${DO_TOKEN:-$DIGITALOCEAN_TOKEN}"
  doctl kubernetes cluster kubeconfig save "${DO_PROJECT_NAME:-rocm-doks-demo}" \
    --access-token "$DIGITALOCEAN_TOKEN" \
    --alias "${DO_PROJECT_NAME:-rocm-doks-demo}" \
    --set-current-context
}

ensure_kube
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --timeout 15m --wait --atomic \
  --set grafana.service.type=LoadBalancer \
  --set prometheus.service.type=LoadBalancer \
  --set alertmanager.service.type=LoadBalancer

helm_install_wait(){ local r="$1" c="$2" ns="$3"; shift 3; kubectl create ns "$ns" --dry-run=client -o yaml|kubectl apply -f - >/dev/null 2>&1||true; retry 3 helm upgrade --install "$r" "$c" -n "$ns" --wait --timeout 10m --atomic "$@"; }

add_repo ingress-nginx https://kubernetes.github.io/ingress-nginx
add_repo prometheus-community https://prometheus-community.github.io/helm-charts
add_repo metrics-server https://kubernetes-sigs.github.io/metrics-server/
add_repo kedacore https://kedacore.github.io/charts
helm repo update


helm_install_wait ingress-nginx ingress-nginx/ingress-nginx ingress-nginx \
  --set controller.metrics.enabled=true --set controller.service.type=LoadBalancer
if [[ "${EXPOSE_MONITORING_LB:-false}" == "true" ]]; then
  helm_install_wait kube-prometheus-stack prometheus-community/kube-prometheus-stack monitoring \
    --set grafana.service.type=LoadBalancer --set prometheus.service.type=LoadBalancer --set alertmanager.service.type=LoadBalancer
else
  helm_install_wait kube-prometheus-stack prometheus-community/kube-prometheus-stack monitoring
fi
helm_install_wait metrics-server metrics-server/metrics-server kube-system \
  --set-string args[0]=--kubelet-insecure-tls --set-string args[1]=--kubelet-preferred-address-types=InternalIP
helm_install_wait keda kedacore/keda keda

# Links
svc_host(){ local ns="$1" name="$2"; local ip host; ip="$(kubectl -n "$ns" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null||true)"; host="$(kubectl -n "$ns" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null||true)"; echo "${ip:-$host}"; }
GRAFANA=kube-prometheus-stack-grafana; PROM=kube-prometheus-stack-prometheus; AM=kube-prometheus-stack-alertmanager

echo "🔐 Grafana admin password:"; kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d || true; echo
for S in "$GRAFANA" "$PROM" "$AM"; do
  H="$(svc_host monitoring "$S")"
  case "$S" in
    "$GRAFANA") T="Grafana"; P=3000; DEF="/";;
    "$PROM")    T="Prometheus"; P=9090; DEF="/";;
    "$AM")      T="Alertmanager"; P=9093; DEF="/";;
  esac
  if [[ -n "$H" ]]; then echo "🔗 $T → http://$H$DEF"; else echo "🔗 $T (port-forward): kubectl -n monitoring port-forward svc/$S $P:${P}"; fi
done

echo "✅ Addons installed."

