# HuginnTrustedAutomation: approved (identity, scope, operation) triples. Never a whole client app.
# Rows come from four places:
#   1. watchlists/HuginnTrustedAutomation.csv (reviewed by hand, committed);
#   2. generated here for Huginn's own deployment principal, whose Terraform refreshes read
#      secrets (storage keys, Logic App callback URL, publishing and ACR credentials) on Huginn's
#      resource groups only;
#   3. generated here for named operators (var.trusted_operators) who run Terraform locally:
#      only listKeys and listCallbackUrl (the two refresh reads seen in lab evidence), only on
#      Huginn's resource groups, each with its own expiry and reason;
#   4. generated here for the Bastion landing zone's CI identities (var.bastion_identities),
#      on Bastion's groups only: listKeys for plan and apply (azurerm refresh), policy denials
#      for the policy tester in bastion-test-rg (Bastion's nightly tests deny on purpose).
# The lab attacker is never added.

locals {
  csv_rows = csvdecode(file("${path.module}/../../watchlists/HuginnTrustedAutomation.csv"))

  # Operations the azurerm provider performs when it refreshes Huginn resources.
  terraform_refresh_ops = [
    "MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION",
    "MICROSOFT.LOGIC/WORKFLOWS/TRIGGERS/LISTCALLBACKURL/ACTION",
    "MICROSOFT.WEB/SITES/CONFIG/LIST/ACTION",
    "MICROSOFT.CONTAINERREGISTRY/REGISTRIES/LISTCREDENTIALS/ACTION",
  ]

  huginn_scopes = [
    for rg in [local.shared.state_resource_group, local.shared.sentinel_resource_group, local.shared.lab_resource_group] :
    lower("${local.subscription}/resourceGroups/${rg}")
  ]

  # Narrower than the deploy principal: the two refresh reads observed in lab evidence.
  operator_ops = [
    "MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION",
    "MICROSOFT.LOGIC/WORKFLOWS/TRIGGERS/LISTCALLBACKURL/ACTION",
  ]

  generated_principals = concat(
    [{
      id         = local.shared.deploy_principal_object_id
      owner      = "huginn"
      reason     = "Huginn GitHub deployment principal: Terraform refresh"
      expires_on = var.trusted_expires_on
      ops        = local.terraform_refresh_ops
    }],
    [for o in var.trusted_operators : {
      id         = o.object_id
      owner      = o.owner
      reason     = o.reason
      expires_on = o.expires_on
      ops        = local.operator_ops
    }],
  )

  generated_rows = flatten([
    for p in local.generated_principals : [
      for scope in local.huginn_scopes : [
        for op in p.ops : {
          PrincipalId = lower(p.id)
          AppId       = ""
          ScopePrefix = scope
          Operation   = op
          Owner       = p.owner
          Reason      = p.reason
          ExpiresOn   = p.expires_on
        }
      ]
    ]
  ])

  # Bastion (github.com/MarwenOnGit/Bastion). "bastion-" is a prefix on purpose: it covers
  # bastion-tfstate-rg and the workload groups, and no Huginn or Fenrir group.
  bastion_scope      = lower("${local.subscription}/resourceGroups/bastion-")
  bastion_test_scope = lower("${local.subscription}/resourceGroups/bastion-test-rg")
  bastion_listkeys   = ["MICROSOFT.STORAGE/STORAGEACCOUNTS/LISTKEYS/ACTION"]
  policy_denial_ops = [
    "MICROSOFT.AUTHORIZATION/POLICIES/DENY/ACTION",
    "MICROSOFT.AUTHORIZATION/POLICIES/DENYACTION/ACTION", # verify in lab: DenyAction may log as deny/action
  ]

  bastion_grants = var.bastion_identities == null ? [] : [
    { id = var.bastion_identities.plan_object_id, scope = local.bastion_scope, ops = local.bastion_listkeys, reason = "Bastion plan identity: azurerm refresh calls listKeys (plan.yml, drift.yml)" },
    { id = var.bastion_identities.apply_object_id, scope = local.bastion_scope, ops = local.bastion_listkeys, reason = "Bastion apply identity: azurerm refresh calls listKeys (apply.yml)" },
    { id = var.bastion_identities.policy_tester_object_id, scope = local.bastion_test_scope, ops = local.policy_denial_ops, reason = "Bastion policy tester: deliberate policy denials (policy-tests.yml)" },
  ]

  bastion_rows = flatten([
    for g in local.bastion_grants : [
      for op in g.ops : {
        PrincipalId = lower(g.id)
        AppId       = ""
        ScopePrefix = g.scope
        Operation   = op
        Owner       = "bastion"
        Reason      = g.reason
        ExpiresOn   = var.bastion_identities.expires_on
      }
    ]
  ])

  watchlist_rows = {
    for row in concat(local.csv_rows, local.generated_rows, local.bastion_rows) :
    uuidv5("url", "huginn:watchlist:${lower(row.PrincipalId)}:${lower(row.ScopePrefix)}:${upper(row.Operation)}") => row
  }
}

resource "azurerm_sentinel_watchlist" "trusted" {
  name                       = "HuginnTrustedAutomation"
  display_name               = "HuginnTrustedAutomation"
  description                = "Approved automation (principal + scope + operation). Managed by Terraform from watchlists/HuginnTrustedAutomation.csv."
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id
  item_search_key            = "PrincipalId"
  labels                     = ["huginn"]
}

resource "azurerm_sentinel_watchlist_item" "trusted" {
  for_each     = local.watchlist_rows
  name         = each.key
  watchlist_id = azurerm_sentinel_watchlist.trusted.id
  properties   = each.value
}
