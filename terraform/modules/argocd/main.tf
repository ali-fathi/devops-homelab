# argocd module
#
# Argo CD GitOps controller installation + AppProject bootstrap.
#
# Phase 2.5 scope (deliberate boundary):
#   - Terraform owns: the AppProject CR (via kubectl_manifest, imported)
#   - Deferred: helm_release take-over of the LIVE Argo CD release
#     (requires a rehearsal on a test cluster first — see phase-2 doc)
#   - NOT Terraform-owned: the app Application CRs under
#     kubernetes/gitops/argocd/applications/ (Argo CD manages them)

# AppProject — declarative project that gates what Argo CD may deploy
resource "kubernetes_manifest" "app_project" {
  manifest = var.app_project_manifest
}
