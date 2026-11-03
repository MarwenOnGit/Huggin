# Shared function and analytics rules.
# Rules are discovered from detections/<tier>/<rule-id>/rule.yaml: adding a rule folder never
# needs a Terraform edit.

locals {
  detections_dir = "${path.module}/../../detections"

  rules_all = {
    for f in fileset(local.detections_dir, "*/*/rule.yaml") :
    yamldecode(file("${local.detections_dir}/${f}")).id => merge(
      yamldecode(file("${local.detections_dir}/${f}")),
      { dir = dirname(f) }
    )
  }

  rules = {
    for id, r in local.rules_all : id => r
    if r.deployable && contains(var.enabled_rules, id) && !contains(var.disabled_rules, id)
  }
}

resource "azurerm_log_analytics_saved_search" "huginn_activity" {
  name                       = "HuginnActivity"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  category                   = "Huginn"
  display_name               = "HuginnActivity"
  function_alias             = "HuginnActivity"
  function_parameters        = ["Ops:dynamic", "Lookback:timespan"]
  query                      = file("${path.module}/../../functions/HuginnActivity.kql")
}

resource "azurerm_sentinel_alert_rule_scheduled" "rule" {
  for_each = local.rules

  # Stable GUID per rule ID, so renaming the display name never recreates the rule.
  name                       = uuidv5("url", "https://github.com/MarwenOnGit/Huggin/detections/${each.key}")
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id
  display_name               = each.value.name
  description = join(" ", [
    "Huginn rule ${each.key} (tier: ${each.value.tier}, status: ${each.value.status}).",
    "Fenrir operations: ${length(each.value.fenrir_ops) > 0 ? join(", ", each.value.fenrir_ops) : "none (beyond Fenrir)"}.",
    "Source: https://github.com/MarwenOnGit/Huggin/tree/main/detections/${each.value.dir}",
  ])
  severity          = each.value.severity
  query             = file("${local.detections_dir}/${each.value.dir}/rule.kql")
  query_frequency   = each.value.frequency
  query_period      = each.value.lookback
  trigger_operator  = "GreaterThan"
  trigger_threshold = each.value.trigger_threshold
  tactics           = each.value.mitre.tactics
  # The Sentinel API takes parent techniques only (T1550, not T1550.001); the full IDs stay in
  # rule.yaml and the rule README.
  techniques = distinct([for t in each.value.mitre.techniques : split(".", t)[0]])

  event_grouping {
    aggregation_method = "AlertPerResult"
  }

  alert_details_override {
    severity_column_name = each.value.severity_column
    display_name_format  = try(each.value.alert_name_format, null)
  }

  dynamic "entity_mapping" {
    for_each = try(each.value.entities, [])
    content {
      entity_type = entity_mapping.value.type
      dynamic "field_mapping" {
        for_each = entity_mapping.value.fields
        content {
          identifier  = field_mapping.key
          column_name = field_mapping.value
        }
      }
    }
  }

  incident {
    create_incident_enabled = true

    grouping {
      enabled = false
    }
  }

  depends_on = [
    azurerm_log_analytics_saved_search.huginn_activity,
    azurerm_sentinel_watchlist_item.trusted,
    azurerm_monitor_diagnostic_setting.activity,
  ]
}
