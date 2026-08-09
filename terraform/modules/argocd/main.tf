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
#
# Provider: alekc/kubectl (kubectl_manifest) — same as MetalLB (2.3).
# It treats CRDs opaquely and supports import with the
# apiVersion//kind//name//namespace ID format,
# unlike hashicorp kubernetes_manifest (no reliable CRD import).

terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }
}

# AppProject — declarative project that gates what Argo CD may deploy
resource "kubectl_manifest" "app_project" {
  yaml_body = yamlencode(var.app_project_manifest)
}
