# k3s-bootstrap module outputs
#
# What callers can consume after the module applies.

output "namespaces" {
  description = "Namespaces created by this module"
  value       = var.namespaces
}
