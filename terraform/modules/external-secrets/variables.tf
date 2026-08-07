# external-secrets module variables
#
# Reserved for the deferred adoption (see main.tf). No inputs needed yet.

variable "namespace" {
  description = "Namespace where External Secrets runs"
  type        = string
  default     = "external-secrets-system"
}
