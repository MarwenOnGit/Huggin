# Huginn status

This file is the single source of truth for what works. A rule is "validated" only after a lab
run produced the expected alert, with a date and evidence. Everything else is a draft.

Last updated: 2026-11-03 (Phase 2, bootstrap applied).

## Environment

| Item | Value | Checked |
|---|---|---|
| Tenant | `972afa9f-85f2-4581-81c4-a126c475a06d` (personal "Default Directory") | 2026-11-03 |
| Subscription | `42146134-9464-4c2d-86b0-afe414704284` (Azure for Students) | 2026-11-03 |
| Region | `francecentral` (allowed by the subscription's "Allowed resource deployment regions" policy, together with italynorth, swedencentral, polandcentral, switzerlandnorth) | 2026-11-03 |
| Entra ID licence | None (`subscribedSkus` empty). Identity tier: written, not deployable. | 2026-11-03 |
| Out of bounds | `fenrir-lab-prod-rg`: Fenrir lab, manual purple-team run only. Huginn and its CI never read, write or delete it. | 2026-11-03 |
| vCPU quota, francecentral | **6 of 6 used** by three deallocated 2-vCPU VMs (`ctf-web-host`, `fenrir-lab-runner-vm`, `fenrir-lab-prod-vm`). Deallocated VMs still count. Blocks the opt-in X-08 VM in this region. | 2026-11-03 |
| Smallest VM size | `Standard_F1als_v7` (1 vCPU, 2 GB, NVMe, Gen2). B1ls and B1s are not offered in francecentral; B2ats_v2 is restricted for this subscription. | 2026-11-03 |
| Tools | Terraform 1.15.6, Azure CLI 2.91.0 + `log-analytics` 1.0.0b3, Python 3.14.4, gh 2.46.0, tflint 0.65.0, checkov 3.4.3 | 2026-11-03 |

## Phases

| Phase | State | Date |
|---|---|---|
| 0. Plan and prerequisites | done | 2026-11-03 |
| 1. Repo layout | done (local only) | 2026-11-03 |
| 2. Infrastructure | written; fmt, validate, tflint, checkov clean. **bootstrap applied** (20 resources). sentinel and lab planned (18 and 5 to add), awaiting approval. | 2026-11-03 |
| 3. Lab evidence | not started | |
| 4. Detections | drafts copied into rule folders, none validated | |
| 5. Testing | static tests only (`make test`) | |
| 6. Documentation | not started | |

## Rules

| Rule | Tier | Fenrir ops | Deployable here | Validation | Status |
|---|---|---|---|---|---|
| `logicapp-callback-listed` | core | X-13 | yes | ci | draft, not yet validated |
| `storage-keys-listed` | core | P-12 | yes | ci (B, C), manual (A) | draft, not yet validated |
| `fenrir-chain` | core | X-08, X-10, X-13, X-14, P-12, P-13 | yes | ci (multi-stage), manual (identity pivot) | draft, not yet validated |
| `vm-runcommand-by-user` | core | X-08 | yes | ci | draft, not yet validated |
| `appservice-publish-creds` | core | X-10 | yes | ci | draft, not yet validated |
| `aci-exec` | core | X-14 | yes | ci | draft, not yet validated |
| `acr-admin-creds-listed` | core | P-13 | yes | ci | draft, not yet validated |
| `mi-control-plane-new-ip` | identity | P-12, P-13 | yes (AzureActivity only) | manual | draft, not yet validated |
| `mi-signin-anomaly` | identity | X-08, X-11 | **no** (P1/P2) | manual | written, not deployable |
| `devicecode-azure-mgmt-signin` | identity | A-02, A-04 | **no** (P1/P2) | manual | written, not deployable |
| `graph-directory-recon` | identity | E-01 to E-07, X-06 | **no** (P1/P2) | manual | written, not deployable |
| `rbac-self-assignment` | beyond-fenrir | none | yes | manual | draft, not yet validated |
| `uai-attached-to-host` | beyond-fenrir | none | yes | manual | draft, not yet validated |
| `automation-runbook-run` | beyond-fenrir | none | yes | manual | draft, not yet validated |

## "Verify in lab" items (Phase 3)

| # | Question | Rules that depend on it | Answer | Evidence |
|---|---|---|---|---|
| 1 | Exact `ActivityStatusValue` strings (`Start`/`Success`/`Failure` or `Started`/`Succeeded`/`Failed`) | all core | open | |
| 2 | Does `Claims_d` keep `idtyp`, `appid`, `xms_mirid` and the object ID claim? | `HuginnActivity`, all core, `mi-control-plane-new-ip` | open | |
| 3 | Is `Caller` the object ID or the app ID for service principals and managed identities? | all core | open | |
| 4 | Do X-10 rows keep `/config/publishingcredentials` in `_ResourceId` or `Properties_d.entity`? | `appservice-publish-creds` | open | |
| 5 | Is X-13's `_ResourceId` the trigger or the workflow? | `logicapp-callback-listed` | open | |
| 6 | Is `Properties_d.requestbody` populated for role assignment and VM writes? | `rbac-self-assignment`, `uai-attached-to-host` | open | |
| 7 | Are X-08, X-14 and P-13 recorded as expected, and how many rows per call? | `vm-runcommand-by-user`, `aci-exec`, `acr-admin-creds-listed` | open | |
| 8 | Ingestion delay from action to `AzureActivity` row (sets the alert timeout in `validate_alert.py`) | CI loop | open | |
| 9 | Does `_GetWatchlist('HuginnTrustedAutomation')` keep the custom columns, and does the function still compile if the watchlist is empty? | `HuginnActivity` | open | |
| 10 | Does `listCallbackUrl` from the azurerm provider (Terraform refresh of the lab Logic App) show up as the deployment principal, so the watchlist must cover it? | `logicapp-callback-listed` | open | |

## Infrastructure facts checked on 2026-11-03 (provider schema and source, azurerm v5.12.0)

| Item | Finding |
|---|---|
| Severity override | `alert_details_override { severity_column_name = "Severity" }` exists in azurerm 5.12.0 |
| Incident settings | Block is `incident { create_incident_enabled, grouping {} }` |
| Techniques | Not validated by the provider. The Sentinel API takes parent techniques, so Terraform sends `T1550` for `T1550.001`. |
| Frequency and period | Provider and Microsoft Learn: both 5 minutes to 14 days, frequency at most the period. No other coupling, so `PT5M` with `P14D` is allowed. |
| Ingestion delay | Sentinel runs scheduled rules 5 minutes after their scheduled time. Microsoft's documented fix for duplicates is an `ingestion_time()` filter. |
| Saved function | `azurerm_log_analytics_saved_search` with `function_alias` and `function_parameters = ["Ops:dynamic", "Lookback:timespan"]` |

## Corrections and changes to the review drafts

| Date | Item | Change | Why |
|---|---|---|---|
| 2026-11-03 | `fenrir-chain` | Removed the `SigninLogs` device code boost from the core rule. The snippet is kept in the rule README for when P1/P2 exists. | Without the Entra connector the `SigninLogs` table does not exist, and a scheduled rule that references a missing table fails to deploy. |
| 2026-11-03 | `mi-control-plane-new-ip`, `graph-directory-recon` | Added a constant `Severity` column. | The drafts had none, and every rule maps alert severity from that column. |
| 2026-11-03 | Plan: lab attacker principal | Moved from `infra/lab` to `infra/bootstrap`. | Creating apps and role assignments needs Graph and User Access Administrator rights. Keeping them in the person-run bootstrap means CI never holds those rights (ADR 0003). |
| 2026-11-03 | Plan: lab attacker federated credential | Subject is the GitHub environment `lab-replay`, not the main branch. | Only replay jobs can obtain the attacker token. |
| 2026-11-03 | Plan: X-13 baseline trap | A new trigger name does not help: the rules key on the workflow, not the trigger. CI replays will create a fresh Logic App per run. | `logicapp-callback-listed` extracts the workflow ID. |

## Open design questions (to settle in Phase 3 or 4)

- **Rule deployment is gated** by `deploy_rules` (default false). Rules are created only after
  Activity log data has reached the workspace and Phase 3 has fixed the drafts.
- **Lab storage with public network access disabled**: confirm at the first lab plan that the
  azurerm provider can still refresh it (blob properties should go through ARM).

- **Duplicate alerts.** Most drafts look at the last 1 hour but run every 5 minutes, so one event
  would raise up to 12 alerts. Options: filter recent events on `ingestion_time()` against the
  rule frequency, or use alert grouping. Rule-level suppression is not an option, because it would
  hide the second replay in the baseline-trap test.
- **Baseline windows and the query period.** Rules with a 14-day baseline need `lookback: P14D`;
  a 1-hour query period would leave the baseline empty and every pair would look new.
