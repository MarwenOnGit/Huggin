# `appservice-publish-creds`

**Status: draft, not yet validated.** Tier: `core`. Validation: `ci`.

Fenrir operations: X-10 (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** retrieval of App Service deployment (Kudu/FTP) credentials or a publish profile. **Fenrir trigger:** `exploit` by default (X-10) on every Kudu-capable site with SCM basic auth on.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## Optional enrichment (not part of the deployed rule)

```kql
// Draft, not yet validated. Basic-auth Kudu logins on the same sites in the next 2 hours.
AppServiceAuditLogs
| where TimeGenerated > ago(2h)
| where Protocol in~ ("Kudu", "FTP", "FTPS", "WebDeploy")
| summarize KuduLogins = count(), KuduIps = make_set(UserAddress, 10) by Site = tolower(_ResourceId)
```

## False positives, false negatives, severity

| | |
|---|---|
| Log source / licence | `AzureActivity`. `AppServiceAuditLogs` needs per-app diagnostic settings. |
| False positives | Portal Configuration blade (app settings / connection strings) if the suffix is not visible: fall back to a "new (caller, site) pair in 14 days" filter. Terraform refresh of `site_credential`: watchlist. Deployment tasks in Azure DevOps / GitHub Actions: watchlist. Visual Studio publish: Medium, triage. |
| False negatives | Credentials read from a publish profile already stored elsewhere (a CI secret). Kudu access with an Entra token instead of basic auth. If the suffix is not logged, the suffix filter drops real events, so test this first. |
| Severity / MITRE | Medium, High for 2+ sites outside a deployment. T1552. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
