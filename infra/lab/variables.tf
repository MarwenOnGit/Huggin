# Opt-in resources cost money per hour or per day. Each is created for one replay run and
# removed afterwards by applying again with the flag back to false (replay.yml does this in an
# always() cleanup step).

variable "enable_vm" {
  description = "X-08: smallest Linux VM for Run Command. Billed per hour while it exists."
  type        = bool
  default     = false
}

variable "enable_appservice" {
  description = "X-10: Linux web app on the Free (F1) plan. No charge, but only one F1 plan per region is allowed on some offers."
  type        = bool
  default     = false
}

variable "enable_aci" {
  description = "X-14: container group running a tiny busybox image. Billed per second while running."
  type        = bool
  default     = false
}

variable "enable_acr" {
  description = "P-13: Basic container registry with the admin user enabled. Billed per day."
  type        = bool
  default     = false
}

variable "vm_location" {
  description = "Region for the opt-in VM only. Defaults to the lab region. The francecentral vCPU quota (6) is currently used by deallocated VMs, so another allowed region may be needed."
  type        = string
  default     = null
}

variable "vm_size" {
  description = "Smallest unrestricted size found in francecentral on 2026-11-03 (B1ls/B1s are not offered there; B2ats_v2 is restricted for this subscription)."
  type        = string
  default     = "Standard_F1als_v7"
}

variable "vm_admin_ssh_public_key" {
  description = "Throwaway SSH public key for the VM (required by Azure for Linux). The replay workflow generates a fresh key pair per run and discards the private key; nobody logs in."
  type        = string
  default     = null

  validation {
    condition     = var.vm_admin_ssh_public_key == null || can(regex("^ssh-(ed25519|rsa) ", var.vm_admin_ssh_public_key))
    error_message = "vm_admin_ssh_public_key must be an OpenSSH public key."
  }
}
