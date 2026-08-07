# longhorn module
#
# Longhorn storage platform installation via Helm.
#
# Longhorn is currently installed via `helm install longhorn longhorn/longhorn`
# (unpinned). Phase 2.4 adopts it into Terraform as a helm_release.
#
# IMPORTANT (Phase 2.4 detail): helm_release has no import for existing
# releases. Adoption requires the documented migration (backup values →
# uninstall release → terraform apply with identical values). PVCs/PVs and
# volume data are NOT managed by the Helm release and survive uninstall.

resource "helm_release" "longhorn" {
  name             = var.release_name
  repository       = var.repository
  chart            = var.chart
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false # namespace must already exist — never recreate
  timeout          = var.timeout
  wait             = true

  # values = var.values  # uncomment when values are provided
}
