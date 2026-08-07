# MetalLB configuration — Terraform-owned (Phase 2.3)
#
# Adopts the live MetalLB CRs (imported, never recreated):
#   IPAddressPool homelab-pool          (was kubernetes/infrastructure/metallb/ip-pool.yaml)
#   L2Advertisement homelab-advertisement (was kubernetes/infrastructure/metallb/l2-advertisement.yaml)
#
# The MetalLB controller itself (metallb-native.yaml) stays kubectl-managed.

module "metallb" {
  source = "./modules/metallb"

  namespace          = "metallb-system"
  pool_name          = "homelab-pool"
  pool_addresses     = ["192.168.178.210-192.168.178.220"]
  advertisement_name = "homelab-advertisement"
}
