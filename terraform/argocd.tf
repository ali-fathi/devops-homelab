# Argo CD AppProject — Terraform-owned (Phase 2.5)
#
# Terraform owns the AppProject CR (the "who may deploy what" gate).
# Loaded from the SAME source file Argo CD uses (single source of truth):
#   kubernetes/gitops/argocd/projects/homelab-platform-project.yaml
#
# Deliberate boundaries (see docs/expansion-plan-phase-2.md):
#   - Terraform owns: the AppProject (kubernetes_manifest, imported)
#   - Deferred: helm_release take-over of the live Argo CD release
#     (require a rehearsal on a test cluster — the live GitOps control
#      plane is not disrupted in this phase)
#   - NOT Terraform-owned: the app Application CRs under
#     kubernetes/gitops/argocd/applications/ (Argo CD manages them)

module "argocd" {
  source = "./modules/argocd"

  app_project_manifest = yamldecode(file("${path.module}/../kubernetes/gitops/argocd/projects/homelab-platform-project.yaml"))
}