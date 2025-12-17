variable "location" {
  type        = string
  description = "Azure region"
  default     = "eastus"
}

variable "project" {
  type        = string
  description = "Project short name used in resource naming"
  default     = "sentineldeploy"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "prod"
}

variable "github_repo" {
  type        = string
  description = "Repo in owner/name form, used for tagging"
  default     = "likeshadic/sentineldeploy"
}

variable "container_image" {
  type        = string
  description = "Full image reference (set by pipeline) e.g. <acrLoginServer>/app:<tag>"
  default     = ""
}

variable "app_port" {
  type        = number
  description = "Container port exposed by the app"
  default     = 8080
}

variable "demo_secret_value" {
  type        = string
  description = "Initial demo secret value stored in Key Vault"
  sensitive   = true
  default     = "change-me"
}