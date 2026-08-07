terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  config_path = "~/.kube/k3s-config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/k3s-config"
  }
}

provider "kubectl" {
  config_path = "~/.kube/k3s-config"
}
