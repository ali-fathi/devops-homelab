# metallb module variables
#
# Inputs for MetalLB configuration. Callers provide the LAN pool and names.

variable "namespace" {
  description = "Namespace where MetalLB CRs live (typically metallb-system)"
  type        = string
  default     = "metallb-system"
}

variable "pool_name" {
  description = "Name of the IPAddressPool"
  type        = string
  default     = "homelab-pool"
}

variable "pool_addresses" {
  description = "List of CIDR/range addresses for the pool (e.g. [\"192.168.178.210-192.168.178.220\"])"
  type        = list(string)
}

variable "advertisement_name" {
  description = "Name of the L2Advertisement"
  type        = string
  default     = "homelab-advertisement"
}
