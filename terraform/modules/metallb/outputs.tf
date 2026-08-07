# metallb module outputs
#
# What callers can consume after the module applies.

output "pool_name" {
  description = "Name of the created IPAddressPool"
  value       = var.pool_name
}

output "advertisement_name" {
  description = "Name of the created L2Advertisement"
  value       = var.advertisement_name
}
