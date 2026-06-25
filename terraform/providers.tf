terraform {
  required_version = ">= 1.7"
}

provider "kubernetes" {
  config_path = "~/.kube/k3s-config"
}
