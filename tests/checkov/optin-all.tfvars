# Used only by checkov (ci.yml, make checkov): turns every opt-in lab resource on, so that
# resources with count = 0 are scanned too (ADR 0004). Never passed to terraform plan/apply.
enable_appservice = true
enable_aci        = true
enable_acr        = true
