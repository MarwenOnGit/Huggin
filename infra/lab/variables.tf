# Opt-in resources cost money per hour or per day. Each is created for one replay run and
# removed afterwards by applying again with the flag back to false (replay.yml does this in an
# always() cleanup step).

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
