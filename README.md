# ROCm GPU on DigitalOcean Kubernetes (DOKS) — Demo Pack

This repo spins up a DOKS cluster, installs core addons, builds & scans a ROCm app (HIP/hipBLAS 1024×1024 GEMM), and deploys it with CPU-fallback while waiting for AMD GPU enablement. It includes HPA (CPU-based by default) and is ready for GPU-aware scheduling and custom-metrics autoscaling once AMD MI300x pools are enabled.

## What you get

- **Terraform** to provision DOKS (v1.31) with a CPU pool and an optional AMD MI300x pool (`amd.com/gpu` resources).
- **Bash scripts** for cluster lifecycle, addon install (ingress, kube-prometheus-stack, Prometheus Adapter, Sealed Secrets, Kubecost), CI-style build+push+scan+deploy, and an HPA demo.
- **Kubernetes manifests** for namespace, Deployment/Service/Ingress, HPA, Prometheus objects, SealedSecret template, and optional KEDA example.
- **App**: a small C++ HIP/hipBLAS GEMM binary invoked by a Flask API (`/compute`) to demonstrate GPU vs CPU (fallback) execution.
- **GitHub Actions** CI pipeline (optional) to build, scan (Trivy), push to DOCR, and deploy.

> ⚠️ If your account is not yet approved for AMD MI300x node pools, set `ENABLE_GPU=false` to skip the GPU pool. You can turn it on later without recreating the cluster.

## Quick start

1. **Install**: `doctl`, `terraform>=1.5`, `kubectl`, `helm`, `kubeseal`, `trivy`, `jq`.
2. **Configure**: copy `.env.example` to `.env` and fill in values, then:
   ```bash
   source .env
   ```
3. **Create cluster & addons**:
   ```bash
   ./scripts/cluster.sh create
   ./scripts/addons-helm.sh
   ```
4. **Build & deploy app** (CPU fallback if GPUs not enabled):
   ```bash
   ./scripts/ci-local.sh
   ```
5. **HPA demo**:
   ```bash
   ./scripts/hpa-demo.sh
   ```

## GPU specifics

- GPU nodes are tainted `amd.com/gpu:NoSchedule` and labeled with AMD/MI300x metadata by DOKS; the Deployment uses `nodeSelector` + `tolerations` to schedule onto GPUs and requests `amd.com/gpu: 1` when enabled.
- We install the **AMD GPU device plugin** via Helm once GPU access is confirmed.

## Clean up

```bash
./scripts/cluster.sh delete
```

See `setup-guide.md` for deeper troubleshooting and interview talking points.
