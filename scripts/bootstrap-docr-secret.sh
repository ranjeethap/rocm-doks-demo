#!/usr/bin/env bash
set -euo pipefail
NS="${1:-dev}"  # dev or prod
doctl registry kubernetes-manifest --namespace "$NS" --name docr-secret \
| kubeseal --controller-namespace kube-system --controller-name sealed-secrets -o yaml \
> "k8s/app/docr-sealedsecret-$NS.yaml"
kubectl apply -f "k8s/app/docr-sealedsecret-$NS.yaml"
echo "✅ Sealed pull secret created for ns=$NS"

