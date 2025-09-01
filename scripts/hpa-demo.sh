#!/usr/bin/env bash
set -euo pipefail

require_cmd kubectl
NAMESPACE="${1:-dev}"
APP="matmul-api"

echo "Watching HPA and nodes; generate load using 'hey' or 'ab' from your workstation:"
echo "  hey -z 60s -c 20 http://$(kubectl -n $NAMESPACE get svc $APP -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080/compute"

kubectl -n "$NAMESPACE" get hpa -w &
kubectl get nodes -w &
wait
