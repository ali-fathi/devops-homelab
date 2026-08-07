# longhorn module outputs

output "release_name" {
  description = "Name of the Longhorn Helm release"
  value       = helm_release.longhorn.name
}

output "namespace" {
  description = "Namespace where Longhorn runs"
  value       = helm_release.longhorn.namespace
}
