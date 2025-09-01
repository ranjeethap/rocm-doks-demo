# Setup & Troubleshooting Guide

## Prereqs
- `doctl auth init` (or export `DO_TOKEN` and scripts will call doctl with `--access-token`)
- `terraform -version` (1.5+)
- `kubectl version --client`
- `helm version`

## Notes
- GPU pool creation requires DO to enable AMD MI300x for your account. Until then, set `ENABLE_GPU=false` in `.env`.
- When GPUs are enabled:
  - Ensure AMD k8s device plugin is installed (`scripts/addons-helm.sh` does this when ENABLE_GPU=true).
  - Your pods must request `resources.limits.amd.com/gpu: "1"` and tolerate the taint `amd.com/gpu:NoSchedule`.

## Common issues
- **422 on GPU pool**: account not yet allow-listed for MI300x. Re-run `terraform apply` after approval.
- **kubectl context mismatch**: run `doctl kubernetes cluster kubeconfig save $CLUSTER_NAME --force`.
- **Helm timeouts**: re-run `scripts/addons-helm.sh` (has built-in retries).

