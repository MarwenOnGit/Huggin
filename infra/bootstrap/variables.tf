variable "tenant_id" {
  description = "Entra ID tenant that holds the lab subscription."
  type        = string
  default     = "972afa9f-85f2-4581-81c4-a126c475a06d"
}

variable "subscription_id" {
  description = "Lab subscription (Azure for Students)."
  type        = string
  default     = "42146134-9464-4c2d-86b0-afe414704284"
}

variable "location" {
  description = "Single region for every Huginn resource. Must be allowed by the subscription's allowed-locations policy."
  type        = string
  default     = "francecentral"
}

variable "github_repository" {
  description = "GitHub owner/name. Combined with the numeric IDs below to build the OIDC subjects."
  type        = string
  default     = "MarwenOnGit/Huginn"
}

variable "github_owner_id" {
  description = "Numeric GitHub ID of the repository owner (gh api repos/MarwenOnGit/Huginn --jq .owner.id)."
  type        = string
  default     = "183097322"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be numeric."
  }
}

variable "github_repository_id" {
  description = "Numeric GitHub ID of the repository (gh api repos/MarwenOnGit/Huginn --jq .id)."
  type        = string
  default     = "1444286931"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be numeric."
  }
}

variable "replay_environment" {
  description = "GitHub Actions environment whose jobs may sign in as the lab attacker."
  type        = string
  default     = "lab-replay"
}

variable "tags" {
  description = "Tags applied to every resource group and resource."
  type        = map(string)
  default = {
    project    = "huginn"
    managed-by = "terraform"
  }
}
