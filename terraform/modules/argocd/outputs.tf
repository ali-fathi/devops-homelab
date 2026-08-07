# argocd module outputs

output "app_project_name" {
  description = "Name of the AppProject managed by this module"
  value       = var.app_project_manifest.metadata.name
}
