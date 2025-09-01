variable "do_token" { 
  type = string 
}
variable "region" {
  type = string
  default = "nyc1"
}
variable "cluster_name" {
  type = string  
  default = "rocm-gpu-demo" 
}
variable "k8s_version" { 
  type = string
  default = "1.31.9-do.3"
}
variable "tags"  {
  type = list(string) 
  default = ["rocm", "demo"]
}

variable "cpu_node_size" {
  type = string
  default = "s-4vcpu-8gb"
}
variable "cpu_node_count"  { 
  type = number
  default = 3 
}
variable "cpu_min_nodes" {
  type = number
  default = 3
}
variable "cpu_max_nodes" {
  type = number
  default = 6 
}

variable "enable_gpu" {
  type = bool
  default = false
}
variable "gpu_node_size" {
  type = string
  default = "gpu-mi300x1-192gb"
}
variable "gpu_node_count"  {
  type = number
  default = 1
}
variable "gpu_min_nodes" {
  type = number
  default = 0
}
variable "gpu_max_nodes" {
  type = number
  default = 2
}

variable "docr_name"  {
  type = string
  default = "rocm-gpu-demo-registry"
}
