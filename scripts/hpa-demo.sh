#!/usr/bin/env bash
set -euo pipefail
NS=dev; SVC=matmul-api
LB=$(kubectl -n $NS get svc $SVC -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
DNS=$(kubectl -n $NS get svc $SVC -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
TARGET=${LB:-$DNS}
if [[ -z "$TARGET" ]]; then kubectl -n $NS port-forward svc/$SVC 8080:8080 >/dev/null 2>&1 & PF=$!; TARGET=localhost; fi
command -v hey >/dev/null || { echo "Install hey (brew install hey)"; exit 1; }
echo "Load for 60s @20c → http://${TARGET}:8080/compute"; hey -z 60s -c 20 "http://${TARGET}:8080/compute" || true
kubectl -n $NS get hpa; kubectl -n $NS get deploy $SVC -o wide
[[ -n "${PF:-}" ]] && kill $PF || true

