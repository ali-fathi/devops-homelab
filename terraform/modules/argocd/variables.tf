# argocd module variables

variable "app_project_manifest" {
  description = "Full manifest for the Argo CD AppProject (loaded from kubernetes/gitops/argocd/projects/)"
  type        = any
}

variable "release_name" {
  description = "Argo CD Helm release name (deferred adoption in Phase 2.5)"
  type        = string
  default     = "argocd"
}

variable "namespace" {
  description = "Namespace for Argo CD"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "argo-cd Helm chart version (pin for reproducibility)"
  type        = string
  default     = ""
}

variable "values_file" {
  description = "Path to values.yaml for the Argo CD chart"
  type        = string
  default     = ""
}
