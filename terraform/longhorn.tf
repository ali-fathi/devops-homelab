# Longhorn storage platform — Terraform-owned (Phase 2.4)
#
# Adopts the live Longhorn Helm release as a helm_release.
# NOTE: helm_release has NO import — adoption requires the documented
# migration (record values/inventory → uninstall release → apply).
# PVCs/PVs/volume data are NOT managed by the Helm release and survive.
#
# The chart_version must be pinned from the LIVE release:
#   helm list -n longhorn-system   → record the CHART column version
#
# The longhorn-frontend-lb Service (kubernetes/infrastructure/longhorn/
# longhorn-ui-lb.yaml) stays kubectl-managed — NOT owned here.

module "longhorn" {
  source = "./modules/longhorn"

  release_name  = "longhorn"
  repository    = "https://charts.longhorn.io"
  chart         = "longhorn"
  chart_version = "1.12.1" # pinned from live: helm list -n longhorn-system (longhorn-1.12.1)
  namespace     = "longhorn-system"
}
