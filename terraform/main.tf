provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_kubernetes_cluster" "this" {
  name    = var.cluster_name
  region  = var.region
  version = var.k8s_version
  tags    = var.tags

  node_pool {
    name       = "cpu-pool"
    size       = var.cpu_node_size
    auto_scale = true
    min_nodes  = var.cpu_min_nodes
    max_nodes  = var.cpu_max_nodes
    labels = {
      role = "cpu"
    }
  }
}

# Optional GPU node pool (AMD MI300x) — only created when enable_gpu=true
resource "digitalocean_kubernetes_node_pool" "gpu" {
  count      = var.enable_gpu ? 1 : 0
  cluster_id = digitalocean_kubernetes_cluster.this.id
  name       = "gpu-pool-amd"
  size       = var.gpu_node_size
  auto_scale = true
  min_nodes  = var.gpu_min_nodes
  max_nodes  = var.gpu_max_nodes

  labels = {
    role = "gpu"
  }

  # DOKS applies amd.com/gpu:NoSchedule taint on GPU nodes (we include for clarity)
  taint {
    key    = "amd.com/gpu"
    value  = ""
    effect = "NoSchedule"
  }
}

# Expose Kubeconfig for local use (optional convenience)
output "kubeconfig" {
  value     = digitalocean_kubernetes_cluster.this.kube_config[0].raw_config
  sensitive = true
}

# Providers configured from the managed cluster
provider "kubernetes" {
  host                   = digitalocean_kubernetes_cluster.this.endpoint
  token                  = digitalocean_kubernetes_cluster.this.kube_config[0].token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = digitalocean_kubernetes_cluster.this.endpoint
    token                  = digitalocean_kubernetes_cluster.this.kube_config[0].token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}
