# k3s-bootstrap module variables
#
# Inputs the caller must (or may) provide.

variable "namespaces" {
  description = "List of platform namespaces to create (e.g. metallb-system, longhorn-system, argocd)"
  type        = list(string)
  default     = []
}

variable "environment" {
  description = "Environment name (homelab, dev, ...)"
  type        = string
  default     = "homelab"
}
