# metallb module
#
# MetalLB configuration for the homelab: IP address pool + L2 advertisement.
#
# These resources currently live in:
#   kubernetes/infrastructure/metallb/ip-pool.yaml
#   kubernetes/infrastructure/metallb/l2-advertisement.yaml
#
# Phase 2.3 will import them into Terraform state so Terraform owns them.
# The metalLB controller itself is installed via helm (metallb repo).

# IP address pool — which LAN IPs MetalLB may assign to LoadBalancer Services
resource "kubernetes_manifest" "ip_address_pool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = var.pool_name
      namespace = var.namespace
    }
    spec = {
      addresses = var.pool_addresses
    }
  }
}

# L2 advertisement — announce assigned IPs over Layer 2 (ARP)
resource "kubernetes_manifest" "l2_advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = var.advertisement_name
      namespace = var.namespace
    }
  }
}
