# The purple stack is applied by a person for one purple-team run and destroyed right after
# (docs/PURPLE-TEAM.md). CI validates and lints it but never applies it.

variable "attacker_object_id" {
  description = "Object ID of the DEDICATED, low-privilege Entra user the operator runs Fenrir as. It gets Contributor on the purple resource group only. Never use an account with rights elsewhere: Fenrir acts on every resource group it can see. Empty = no assignment (grant access by hand)."
  type        = string
  default     = ""

  validation {
    condition     = var.attacker_object_id == "" || can(regex("^[0-9a-f-]{36}$", var.attacker_object_id))
    error_message = "attacker_object_id must be empty or a lower-case GUID."
  }
}

variable "run_label" {
  description = "Free text tag for this run, for example the date. Stored as the huginn-purple tag on every resource."
  type        = string
  default     = "manual"
}

variable "enable_vm" {
  description = "X-08 target: Linux VM with a user-assigned identity and host logs (Syslog through the Azure Monitor Agent). Uses 2 vCPU of the regional quota while it exists."
  type        = bool
  default     = true
}

variable "vm_size" {
  description = "VM size. Standard_B2ats_v2 is the smallest size this subscription can use in francecentral (docs/STATUS.md)."
  type        = string
  default     = "Standard_B2ats_v2"
}

variable "enable_webapp" {
  description = "X-10/X-11 target: Linux web app with SCM basic auth on. Only one Free (F1) plan per region is allowed on some offers, so turn off enable_appservice in infra/lab first."
  type        = bool
  default     = true
}

variable "webapp_sku" {
  description = "App Service plan SKU. F1 is free; some diagnostic categories need B1 or higher."
  type        = string
  default     = "F1"
}

variable "enable_aci" {
  description = "X-14 target: container group running an idle busybox. Billed per second."
  type        = bool
  default     = true
}

variable "enable_acr" {
  description = "P-13/D-03 target: Basic registry with the admin user on. Billed per day."
  type        = bool
  default     = true
}

variable "enable_defender_arm" {
  description = "Microsoft Defender for Resource Manager on the WHOLE subscription. Paid after the trial. The only Microsoft source that analyses Resource Manager traffic beyond the Activity log, so the run can test whether it sees Fenrir's reads. Off by default."
  type        = bool
  default     = false
}

variable "canary_expires_on" {
  description = "Expiry of the Key Vault canary secret (RFC 3339)."
  type        = string
  default     = "2027-06-30T00:00:00Z"
}
