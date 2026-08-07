# metallb module
#
# MetalLB configuration for the homelab: IP address pool + L2 advertisement.
#
# These resources currently live in:
#   kubernetes/infrastructure/metallb/ip-pool.yaml
#   kubernetes/infrastructure/metallb/l2-advertisement.yaml
#
# Phase 2.3 imports them into Terraform state so Terraform owns them.
# The MetalLB controller itself is installed via the metallb-native.yaml
# manifest (kubectl), NOT managed here.
#
# Provider choice: alekc/kubectl (kubectl_manifest) — treats CRDs opaquely,
# avoiding the huge CRD schema that hashicorp kubernetes_manifest requires.

terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }
}

# IP address pool — which LAN IPs MetalLB may assign to LoadBalancer Services
resource "kubectl_manifest" "ip_address_pool" {
  yaml_body = <<-EOT
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: ${var.pool_name}
      namespace: ${var.namespace}
    spec:
      addresses:
        - ${var.pool_addresses[0]}
  EOT
}

# L2 advertisement — announce assigned IPs over Layer 2 (ARP)
resource "kubectl_manifest" "l2_advertisement" {
  yaml_body = <<-EOT
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: ${var.advertisement_name}
      namespace: ${var.namespace}
  EOT
}
