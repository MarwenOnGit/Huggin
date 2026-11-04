# Huggin status

This file is the single source of truth for what works. A rule is "validated" only after a lab
run produced the expected alert, with a date and evidence. Everything else is a draft.

Last updated: 2026-11-04 (Phase 6 docs).

## Environment

| Item | Value | Checked |
|---|---|---|
| Tenant | `972afa9f-85f2-4581-81c4-a126c475a06d` (personal "Default Directory") | 2026-11-03 |
| Subscription | `42146134-9464-4c2d-86b0-afe414704284` (Azure for Students) | 2026-11-03 |
| Region | `francecentral` (allowed by the subscription's "Allowed resource deployment regions" policy, together with italynorth, swedencentral, polandcentral, switzerlandnorth) | 2026-11-03 |
| Entra ID licence | None (`subscribedSkus` empty). Identity tier: written, not deployable. | 2026-11-03 |
| Out of bounds | `fenrir-lab-prod-rg`: Fenrir lab, manual purple-team run only. Huggin and its CI never read, write or delete it. | 2026-11-03 |
| vCPU quota, francecentral | Was 6 of 6 (three deallocated 2-vCPU VMs). After the operator deleted two VMs: **2 of 6** regional; Basv2 family 0 of 10. Deallocated VMs still count. | 2026-11-03 |
| Smallest VM size | **`Standard_B2ats_v2`** (2 vCPU, 1 GB, x64, Gen2, Basv2 family). Correction: the Phase 2 check dropped every size with any restriction, but B-series v2 restrictions are **zone-only** (zones 2, 3), so a non-zonal VM is allowed. `Standard_F1als_v7` cannot be used: its family quota is 0 of 0, like every 1-vCPU size left in the region. B1ls and B1s are not offered in francecentral. | 2026-11-03 |
| Tools | Terraform 1.15.6, Azure CLI 2.91.0 + `log-analytics` 1.0.0b3, Python 3.14.4, gh 2.46.0, tflint 0.65.0, checkov 3.4.3 | 2026-11-03 |

## Phases

| Phase | State | Date |
|---|---|---|
| 0. Plan and prerequisites | done | 2026-11-03 |
| 1. Repo layout | done (local only) | 2026-11-03 |
| 2. Infrastructure | **Applied**: bootstrap (20), sentinel (18, no rules: `deploy_rules = false`), lab always-on (5). Second plan of sentinel and lab: no changes. | 2026-11-03 |
| 3. Lab evidence | X-13 and P-12 captured as the lab attacker (`lab-evidence/`). Items 1, 3, 5, 8, 10 answered; 2 answered except managed identity. OIDC subject fix applied. Export gap resolved for new events. Still to do: X-08, X-10, X-14, P-13 (opt-in resources), item 4, item 6, item 7. | 2026-11-03 |
| 4. Detections | Demo set (`logicapp-callback-listed`, `storage-keys-listed`, `fenrir-chain` multi-stage) rewritten with ingestion-time dedup, tested ad hoc on real rows (fire with a wide window, silent with the real 5-minute window). Sentinel apply 2026-11-03 **partly failed**: function replaced, 6 operator watchlist rows created, `fenrir-chain` created and enabled (PT5M/PT4H). `logicapp-callback-listed` and `storage-keys-listed` rejected (PT5M with P14D not allowed). **Decision (option A):** PT5M with PT47H and `Baseline = 47h`; re-tested ad hoc on real rows (fire with a wide window, silent at 5 minutes; storage rule no longer flags the operator, so the operator watchlist rows work). 2 rules applied 2026-11-03: all 3 demo rules **enabled** in Sentinel (PT5M; P1DT23H, P1DT23H, PT4H). First replay run (21:17Z) used `main` with `PT47H`, so its drift check is expected to fail until the `P1DT23H` fix is pushed. Opt-in batch (X-08, X-10, X-14, P-13) postponed until after 11 November. | 2026-11-03 |
| 5. Testing | `ci.yml` **green** on its first run (41738746348, commit `e598ae1`): static tests 74 passed, KQL parser 15/15 files, shellcheck clean, fmt/validate, tflint, checkov 0 failed in both passes. KQL self-test added 2026-11-04 (`tests/kql_check/fixtures/broken`, `--expect-errors`): CI now proves on every run that the parser rejects broken queries; first run pending. `replay.yml` green twice back to back (41728291675, 41734608159): baseline-trap test passed. Static tests enforce frequency/lookback, duration format, dedup window, entity columns and validated-status evidence. Nightly runs at 02:30 UTC. | 2026-11-03 |
| 6. Documentation | README rewritten (pitch, diagram, tiers with status, test loops, quick start, cost, teardown, blind spots, naming, roadmap); ARCHITECTURE.md (Mermaid data flow and test loop, licence split, trust boundaries, stacks); DEMO.md (5-minute script, short answers); PURPLE-TEAM.md (operator checklist); ADRs 0006, 0007 and an ADR index; blind-spots section in FENRIR-MAPPING. | 2026-11-04 |

## Rules

| Rule | Tier | Fenrir ops | Deployable here | Validation | Status |
|---|---|---|---|---|---|
| `logicapp-callback-listed` | core | X-13 | yes | ci | **validated 2026-11-03** |
| `storage-keys-listed` | core | P-12 | yes | ci (B, C), manual (A) | **validated 2026-11-03** (branch C) |
| `fenrir-chain` | core | X-08, X-10, X-13, X-14, P-12, P-13 | yes | ci (multi-stage), manual (identity pivot) | **validated 2026-11-03** (multi-stage) |
| `vm-runcommand-by-user` | core | X-08 | yes | ci | **validated 2026-11-03** |
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
| 1 | Exact `ActivityStatusValue` strings (`Start`/`Success`/`Failure` or `Started`/`Succeeded`/`Failed`) | all core | **Answered (workspace, 2026-11-03):** `ActivityStatusValue` is `Start`, `Success`, `Failure`. `ActivitySubstatusValue` is `OK` on success, `NotFound` on the failed X-13 probe. (The raw Activity log API shows `Started`/`Succeeded`/`Failed` instead.) The drafts accept both forms, so no change needed. | `lab-evidence/X-13.json`, `lab-evidence/P-12.json` (run 2026-11-03T20:44Z) |
| 2 | Does `Claims_d` keep `idtyp`, `appid`, `xms_mirid` and the object ID claim? | `HuginnActivity`, all core, `mi-control-plane-new-ip` | **Answered for service principals (workspace):** `Claims_d` keeps `idtyp` (`app`), `appid` (client ID) and the object ID under `http://schemas.microsoft.com/identity/claims/objectidentifier`. For users (raw API): `idtyp`, `appid`, `objectidentifier` present. `xms_mirid`: absent for both, as expected. **Managed identity: open**, moved to the manual purple-team run (Huggin CI must not replay MI tokens). | `lab-evidence/X-13.json`, `lab-evidence/P-12.json` (run 2026-11-03T20:44Z) |
| 3 | Is `Caller` the object ID or the app ID for service principals and managed identities? | all core | **Answered (workspace):** for a service principal, `Caller` is the **service principal object ID** (`380b1f3c-...`), not the app ID (`a9d1d6db-...`, which is in `Claims_d.appid`). For a user, `Caller` is the UPN. Managed identity: open (purple-team run). | `lab-evidence/X-13.json`, `lab-evidence/P-12.json` (run 2026-11-03T20:44Z) |
| 4 | Do X-10 rows keep `/config/publishingcredentials` in `_ResourceId` or `Properties_d.entity`? | `appservice-publish-creds` | open | |
| 5 | Is X-13's `_ResourceId` the trigger or the workflow? | `logicapp-callback-listed` | **Answered (workspace):** `_ResourceId` and `Properties_d.entity` are the **trigger** (`.../workflows/logic-huginn-lab/triggers/manual`). The draft's `extract("^(.*/workflows/[^/]+)")` returns the workflow, as intended. | `lab-evidence/X-13.json`, `lab-evidence/P-12.json` (run 2026-11-03T20:44Z) |
| 6 | Is `Properties_d.requestbody` populated for role assignment and VM writes? | `rbac-self-assignment`, `uai-attached-to-host` | **Partial (2026-11-03):** `Properties_d.requestbody` is **empty** on `VIRTUALMACHINES/WRITE` rows when the VM is created by `az vm create` (the write runs inside an ARM deployment; `InDeployment = true`), and on Run Command rows (the command text is not logged). Direct PUTs and role assignment writes: still open. | X-08 evidence run 41725250751; ad-hoc query 2026-11-03 |
| 7 | Are X-08, X-14 and P-13 recorded as expected, and how many rows per call? | `vm-runcommand-by-user`, `aci-exec`, `acr-admin-creds-listed` | **X-08 answered (2026-11-03):** one Run Command call = **3 rows**, `Start`, `Accept` (sub-status `Accepted`), `Success`, one `CorrelationId`, `_ResourceId` = the VM. Ingested 7 to 10 minutes after the action, and not together (Success 21:58:02; Start and Accept 22:00:26). X-14 and P-13: postponed with the opt-in batch. | `lab-evidence/X-08.json` |
| 8 | Ingestion delay from action to `AzureActivity` row (sets the alert timeout in `validate_alert.py`) | CI loop | **Measured:** 3 min 0 s to 4 min 24 s from `TimeGenerated` to `ingestion_time()` for the six evidence rows (one run, 2026-11-03). Expected time-to-alert with a 5-minute rule: up to about 15 minutes. Re-measure in Phase 5. | `lab-evidence/X-13.json`, `lab-evidence/P-12.json` (run 2026-11-03T20:44Z) |
| 9 | Does `_GetWatchlist('HuginnTrustedAutomation')` keep the custom columns, and does the function still compile if the watchlist is empty? | `HuginnActivity` | partial: custom columns are kept and the function compiles with the watchlist populated (2026-11-03). The empty case is untested; Terraform always adds the deploy principal rows, so it does not arise. | |
| 10 | Does `listCallbackUrl` from the azurerm provider (Terraform refresh of the lab Logic App) show up as the deployment principal, so the watchlist must cover it? | `logicapp-callback-listed` | **Answered:** yes. Terraform refresh calls `listCallbackUrl` and `listKeys` (even with shared keys disabled) as whoever runs it. In the workspace, the operator's bootstrap plan/apply at 20:40 and 20:42 UTC produced `listKeys` on the **state** account as the user (Azure CLI app ID), and the `storage-keys-listed` draft flags it (branch C). The deploy principal is watchlisted; the operator is not (use `trusted_operator_object_ids` if wanted). | `lab-evidence/X-13.json`, `lab-evidence/P-12.json` (run 2026-11-03T20:44Z); ad-hoc draft run 2026-11-03 |

## Deployed (2026-11-03)

| Item | Value |
|---|---|
| Workspace | `law-huginn` in `huginn-sentinel-rg`, workspace ID `b15fe383-5018-4ce4-ada1-6e06f8c83bee` |
| State | `sthuginntfb8182282bc` / `tfstate` (sentinel.tfstate, lab.tfstate). Bootstrap state is local. |
| Deploy principal | `huginn-github-deploy`, client `7dc8cd97-cd36-4c93-ba16-c0cc0c2dd6e7`, object `efb16475-4aa5-4d35-a8ff-52239d1c6e02`. Federated subject: main branch only. |
| Lab attacker | `huginn-lab-attacker`, client `a9d1d6db-367e-4648-a22c-3b29cfc23a7b`, object `380b1f3c-3bf0-44de-b940-e035eb1a0084` |
| Lab | `logic-huginn-lab` (trigger `manual`), `sthuginnlab30e2449d`, `id-huginn-lab` |
| Function | `HuginnActivity(...)` compiles and runs against the workspace (0 rows, before Activity log data arrived) |
| Activity log connector | Working. First rows at 16:41 local: `MICROSOFT.OPERATIONSMANAGEMENT/SOLUTIONS/WRITE` (the Sentinel onboarding itself), ingestion lag about 9 minutes. |
| Watchlist | All 12 rows readable through `_GetWatchlist` after about 10 minutes (6 were visible right after apply). |
| Lab storage, public network disabled | Terraform refresh works (no drift), so blob properties are read through ARM. Open question closed. |

## Infrastructure facts checked on 2026-11-03 (provider schema and source, azurerm v5.12.0)

| Item | Finding |
|---|---|
| Severity override | `alert_details_override { severity_column_name = "Severity" }` exists in azurerm 5.12.0 |
| Incident settings | Block is `incident { create_incident_enabled, grouping {} }` |
| Techniques | Not validated by the provider. The Sentinel API takes parent techniques, so Terraform sends `T1550` for `T1550.001`. |
| Frequency and period | Provider and Microsoft Learn: both 5 minutes to 14 days, frequency at most the period. **Wrong conclusion corrected 2026-11-03:** the Sentinel API also enforces "when queryPeriod >= 2 days, queryFrequency must be >= 1 hour" (400 BadRequest on apply). The docs page read did not mention it, and I recorded "no other coupling" without testing it. |
| Ingestion delay | Sentinel runs scheduled rules 5 minutes after their scheduled time. Microsoft's documented fix for duplicates is an `ingestion_time()` filter. |
| Saved function | `azurerm_log_analytics_saved_search` with `function_alias` and `function_parameters = ["Ops:dynamic", "Lookback:timespan"]` |

## Corrections and changes to the review drafts

| Date | Item | Change | Why |
|---|---|---|---|
| 2026-11-03 | `fenrir-chain` | Removed the `SigninLogs` device code boost from the core rule. The snippet is kept in the rule README for when P1/P2 exists. | Without the Entra connector the `SigninLogs` table does not exist, and a scheduled rule that references a missing table fails to deploy. |
| 2026-11-03 | `mi-control-plane-new-ip`, `graph-directory-recon` | Added a constant `Severity` column. | The drafts had none, and every rule maps alert severity from that column. |
| 2026-11-03 | Plan: lab attacker principal | Moved from `infra/lab` to `infra/bootstrap`. | Creating apps and role assignments needs Graph and User Access Administrator rights. Keeping them in the person-run bootstrap means CI never holds those rights (ADR 0003). |
| 2026-11-03 | Plan: lab attacker federated credential | Subject is the GitHub environment `lab-replay`, not the main branch. | Only replay jobs can obtain the attacker token. |
| 2026-11-03 | OIDC federated credential subjects | Rebuilt from GitHub's ID-based format `repo:MarwenOnGit@183097322/Huggin@1444286931:...` (variables `github_owner_id`, `github_repository_id`). Removed the deploy identity's `pull_request` credential. | The first evidence run failed with `AADSTS700213`: the repository uses immutable subjects (`use_immutable_subject: true`), so the name-only subjects never matched. ADR 0003. |
| 2026-11-03 | Facts table: frequency and period | Corrected: PT5M with P14D is rejected by the Sentinel API (period >= 2 days needs frequency >= 1 hour). | Found by a failed apply. Earlier entry was a documentation reading, not a test. |
| 2026-11-03 | `logicapp-callback-listed`, `storage-keys-listed` | Lookback P14D to PT47H, KQL `Baseline = 47h`, frequency stays PT5M. | Sentinel API rule (period >= 2 days needs frequency >= 1 hour). Option A, ADR 0005. Option C on the roadmap. |
| 2026-11-03 | X-08 lab VM | No longer a Terraform opt-in resource. Terraform keeps only a free VNet, subnet and deny-all-inbound NSG; each evidence or replay run creates a fresh `Standard_B2ats_v2` VM (no public IP, no identity, throwaway SSH key deleted before the VM exists, OS disk and NIC deleted with it), runs `hostname`, and deletes it through a trap, with `cleanup.sh` as a safety net. | The VM must never outlive a run, running or deallocated (quota). A per-run VM also gives a fresh (caller, VM) pair. |
| 2026-11-04 | Project name | "Huginn" renamed to **Huggin** in all Markdown (29 occurrences, 16 files, including the four review docs). Deployed identifiers keep the old spelling: `HuginnActivity`, `HuginnTrustedAutomation`, `huginn-*` resource groups and apps, rule titles "Huginn - ...". | Operator's correction; renaming deployed names needs Azure changes. |
| 2026-11-03 | Deduplication in all four Phase 4 rules | Upper bound `<= now()` on "new"; per-request (`CorrelationId`) counting in `vm-runcommand-by-user` and `fenrir-chain`. | Duplicate alerts on the first green replay; see "First alerts and the duplicate-alert defect". |
| 2026-11-03 | `vm-runcommand-by-user` | Rewritten from X-08 evidence: dedup per request, Medium (not Low) for unknown service principals, entities, alert title; added to `enabled_rules`; `replay.sh` with a fresh VM per run. | Lab evidence X-08. |
| 2026-11-03 | `evidence.yml` | `ops` input has no default. | Run 41724390758 meant to do X-08 but ran the default ops. |
| 2026-11-03 | X-08 network applied | `vnet-huginn-lab` / `snet-vm` / `nsg-huginn-lab-vm` (4 resources, no drift). Subnet `defaultOutboundAccess: true` (azurerm sets it explicitly, so the subnet is not private); NSG: custom deny-all inbound at 4000, default `AllowInternetOutBound`. No NAT gateway or public IP. | Microsoft Learn (Run Command, Restrictions): outbound 443 to Azure public IPs is needed to return script results. `cleanup.sh` checked: only lists `-g huginn-lab-rg`, and `huginn_delete` refuses any ID outside that resource group (stub test 2026-11-03). |
| 2026-11-03 | Smallest VM size | `Standard_F1als_v7` to `Standard_B2ats_v2`. | F1als_v7 family quota is 0; earlier "B2ats_v2 restricted" was a zone-only restriction misread. |
| 2026-11-03 | `scripts/replay/lib.sh` run ID | Created once in `huginn_preflight`. | It was created inside `$(...)` on every call, so tags did not match resource names. |
| 2026-11-03 | `logicapp-callback-listed`, `storage-keys-listed` lookback | `PT47H` rewritten as `P1DT23H` (same duration). Static test rejects hour counts of 24 or more. | Sentinel stores `PT47H` as `P1DT23H`, so Terraform showed a permanent 2-change diff after apply, which would make every `replay.yml` drift check fail. |
| 2026-11-03 | `acr-admin-creds-listed`, `mi-control-plane-new-ip` | Frequency PT5M / PT15M to PT1H, lookback stays P14D. | Same API rule; caught by the new static test. Not deployed, not time-critical. |
| 2026-11-03 | `storage-keys-listed` branch B | Marked `manual`, not `ci`. | A replay with one fresh account per run does not exercise "3+ accounts in 1 hour". |
| 2026-11-03 | `replay.yml` | Checks drift (`terraform plan` must show no changes) instead of applying. | Keeps every Azure change manual and reviewed. ADR 0005. |
| 2026-11-03 | checkov CKV_AZURE_249 | Skipped inline as a false positive on both federated credentials. | checkov's repo pattern does not accept GitHub's `owner@id/repo@id` subjects. ADR 0004. |
| 2026-11-03 | Plan: X-13 baseline trap | A new trigger name does not help: the rules key on the workflow, not the trigger. CI replays will create a fresh Logic App per run. | `logicapp-callback-listed` extracts the workflow ID. |

## Incident: AzureActivity export gap (resolved for new events, 2026-11-03)

The subscription diagnostic setting `huginn-activity-to-law` exists with Administrative, Security,
Policy and Alert enabled. The raw Activity log shows about 40 Huggin events between 15:30 and
15:42 UTC, but by 20:14 UTC the workspace held only 2 rows (both at 15:30:36, the Sentinel
solution write). No cap was hit (`Usage`: AzureActivity 0.016 MB, non-billable) and `_LogOperation`
is empty. There were no subscription events after 15:42, so whether the export works now is
unknown. Suspects, not yet tested: a slow start of a new subscription diagnostic setting, or
`local_authentication_enabled = false` on the workspace (no documentation found either way).

**Update 20:50 UTC.** The evidence run at 20:44 UTC reached the workspace in 3 to 4.5 minutes,
with no configuration change (`local_authentication_enabled` was left at `false`). So the export
works with local auth disabled, and that suspect is ruled out. The 15:31 to 15:42 UTC events were
never exported; the most likely cause is the start-up of the new diagnostic setting, but this is
not confirmed. Lesson for Phase 5: do not trust the first minutes after creating a diagnostic
setting, and always check the workspace, not only the raw Activity log.

## First alerts and the duplicate-alert defect (2026-11-03)

- **First green replay:** `replay.yml` run 41720948678 (21:20:45 UTC, after the `P1DT23H` fix):
  drift OK, replays OK, all 3 rules fired for the lab attacker. Time to alert:
  `logicapp-callback-listed` 10 min 24 s, `storage-keys-listed` 10 min 35 s, `fenrir-chain`
  7 min 24 s. Incidents 4 to 7.
- **`fenrir-chain` also fired on evidence run 41724390758** (X-13 + P-12 at 21:43:58): 5 min 5 s.
  Rules 1 and 2 stayed silent for that run, as they should (pairs already seen within 47 h).
- **Defect: duplicates.** The same replay events raised 2 alerts each for rules 1 and 2
  (window ends 21:27 and 21:32) and 3 for `fenrir-chain` (21:24, 21:29, 21:34). Cause: in a
  scheduled rule `now()` is the window end (`Query End Time UTC`), but the query runs about 5
  minutes later, so `ingestion_time() > ago(5m)` matched rows ingested in that gap in two runs.
  Proven by decoding the alerted rows (`ExtendedProperties.Query`) and comparing with the rows'
  ingestion times.
- **Fix (deployed 2026-11-03 with `vm-runcommand-by-user`; 1 added, 3 changed; re-plan of sentinel and lab: no changes):** `IngestedAt > ago(5m) and IngestedAt <= now()`; aggregating
  rules count a request (`CorrelationId`) once, when its first row is ingested; `fenrir-chain`
  only sees rows ingested by `now()`. A read-only simulation pinned to the real window ends
  reproduced the deployed rules' real alerts exactly, then gave 1 alert per event for rules 1, 2
  and `vm-runcommand-by-user`, and 1 alert per window with new requests for `fenrir-chain`.
- **Post-fix replay 1 (baseline-trap run 1 of 2):** `replay.yml` run 41728291675 (22:09:33 UTC,
  commit `a62758a`): drift OK, replays OK (2 min 14 s incl. VM), cleanup 0 left, all 4 rules fired.
  Alerts per rule for the run: `logicapp-callback-listed` 1 (16 min 46 s), `storage-keys-listed` 1
  (16 min 46 s), `vm-runcommand-by-user` 1 (11 min 45 s), `fenrir-chain` 2 (11 min 39 s; windows
  22:17 and 22:22, two windows with new requests, the documented behaviour). Incidents 14 to 18.
- **Post-fix replay 2 (baseline-trap run 2 of 2):** `replay.yml` run 41734608159 (22:53:09 UTC,
  commit `2fb4431`), started right after run 1 with the same lab attacker: drift OK, replays OK
  (2 min 18 s incl. VM), cleanup 0 left, 0 VMs in `huginn-lab-rg`. Exactly **1 alert per rule**
  (re-counted at 23:16, after the next window): all four at about 12 min 45 s (one window,
  23:02). Incidents 19 to 22. **Baseline-trap test passed**: fresh resources per run keep the
  "new pair" rules firing for the same caller.
- **First scheduled (nightly) replay:** run 41808405680 on 2026-11-04, commit `9943ab6`, green:
  drift OK, replays OK, cleanup 0 left, exactly 1 alert per rule. GitHub started it at 09:32 UTC,
  7 hours after the 02:30 cron time (scheduled workflows are best-effort and can be delayed).
- **Third `vm-runcommand-by-user` alert explained (2026-11-04):** the rule has 3 alerts for 3 real
  Run Command events: its first run after deployment (window end 22:02:19) caught the X-08
  evidence run of 21:50 (rows ingested 21:58 and 22:00), then one alert per back-to-back replay.
  Not a duplicate.
- **Defender XDR (seen 2026-11-04):** the Defender portal lists `law-huginn` as **Connected,
  Primary**, and incidents show `ProviderName = Microsoft XDR`. Huggin's Terraform did not do
  this, and it was already connected when the operator first opened the Defender portal; how it
  got connected is not confirmed. The Azure portal says Sentinel will only be available in the
  Defender portal after 31 March 2027; analytics rules are already shown only there.
- **Validated (2026-11-03):** `logicapp-callback-listed`, `storage-keys-listed` (branch C),
  `fenrir-chain` (multi-stage branch), `vm-runcommand-by-user`. Evidence: replays 41728291675 and
  41734608159, both green, one alert per event. Not covered: storage branches A and B,
  `fenrir-chain` identity pivot (purple-team run).

## Draft rules run ad hoc on real rows (2026-11-03, read-only, not deployed)

| Rule | Result | Note |
|---|---|---|
| `logicapp-callback-listed` | 1 result: the lab attacker, `logic-huginn-lab`, Medium | Counts the failed attempt on a missing trigger too (same workflow). Acceptable: an attempt is still a signal. |
| `storage-keys-listed` | 2 results, both branch C: the lab attacker on `sthuginnlab30e2449d` (expected), and the operator on the state account (Terraform refresh) | The second is a real false positive from the operator running Terraform locally. |

This is not validation: the rules are not deployed, and no alert or incident was produced.

## Open design questions (to settle in Phase 3 or 4)

- **Rule deployment** is now per rule: `enabled_rules` in `infra/sentinel/huginn.auto.tfvars.json` (replaces `deploy_rules`).
- **Duplicate alerts: settled (2026-11-03)** for the three demo rules: `ingestion_time() > ago(Frequency)`
  selects new rows; baselines use earlier rows (docs/TESTING.md, ADR 0005). Checked ad hoc: the
  same rows fire with a wide window and give 0 rows with the real 5-minute window. The other
  drafts still use the old pattern and get the same change when they are worked on.
- **Baseline windows and the query period.** Rules with a 14-day baseline need `lookback: P14D`;
  a 1-hour query period would leave the baseline empty and every pair would look new.
