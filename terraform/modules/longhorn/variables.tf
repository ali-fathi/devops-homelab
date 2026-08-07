# longhorn module variables

variable "release_name" {
  description = "Helm release name (must match existing live release for adoption)"
  type        = string
  default     = "longhorn"
}

variable "repository" {
  description = "Helm chart repository"
  type        = string
  default     = "https://charts.longhorn.io"
}

variable "chart" {
  description = "Helm chart name"
  type        = string
  default     = "longhorn"
}

variable "chart_version" {
  description = "Helm chart version (pin for reproducibility)"
  type        = string
  default     = "" # unpinned — pin after recording live version
}

variable "namespace" {
  description = "Namespace for Longhorn (must already exist)"
  type        = string
  default     = "longhorn-system"
}

variable "timeout" {
  description = "Helm install timeout in seconds"
  type        = number
  default     = 600
}

variable "values" {
  description = "YAML values for the Longhorn chart"
  type        = string
  default     = ""
}
