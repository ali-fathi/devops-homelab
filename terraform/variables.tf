variable "environment" {
  default = "homelab"
}

variable "kubeconfig_path" {
  description = "Absolute path to the kubeconfig (tilde does NOT expand in all providers)"
  type        = string
  default     = "~/.kube/k3s-config"
}
