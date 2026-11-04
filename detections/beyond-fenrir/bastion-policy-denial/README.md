# `bastion-policy-denial`

**Status: draft, not yet validated.** Tier: `beyond-fenrir`. Validation: `manual`.

**Fenrir does not trigger this rule.** Fenrir makes no writes, and Azure Policy cannot block its
POST actions. The rule covers the writes an operator tries next (a VM, a public IP, a storage
account with shared keys, deleting a diagnostic setting) when they land in the
[Bastion landing zone](https://github.com/MarwenOnGit/Bastion).

Fenrir operations: none (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a request refused by Bastion's `bastion-baseline` policy assignment, by anyone
except Bastion's own policy tester. **Source:** Bastion's
[PREVENT-DETECT.md](https://github.com/MarwenOnGit/Bastion/blob/main/docs/PREVENT-DETECT.md),
"Every prevented attempt is also a detection". Huggin already exports the subscription Activity
log's `Policy` category (`activity_log_categories` in `infra/sentinel/variables.tf`), so no new
data source is needed.

## Query

See [rule.kql](rule.kql). Changes from Bastion's query:

- Uses `HuginnActivity`, so the watchlist exclusion and caller kind work as in the other rules.
- Counts each row once (`IngestedAt` window, as in the core rules), then summarises the last hour
  of denials for the callers that have new rows.
- Also accepts `POLICIES/DENYACTION/ACTION` until the lab shows how a DenyAction (delete) refusal
  is logged.
- Ignores `bastion-baseline-audit`: that assignment is audit-only and never denies.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Bastion's nightly policy tests (excluded by watchlist once `bastion_identities` is set in `huginn.auto.tfvars.json`; until then every test denial alerts, so do not enable the rule before that). A person or pipeline pushing a non-compliant change by mistake: Low, triage. |
| False negatives | Anything outside the Bastion groups (no Bastion policy there). Controls still in their audit effect (no denial is written). An attacker who reads the assignment first and only sends compliant requests. |
| Severity / MITRE | High for a managed identity (Fenrir's post-exploit caller). Medium for 3 or more attempts or controls in an hour, or for any attempt to delete a diagnostic setting (`protect-diagnostic-settings`). Low otherwise. T1578 (modify cloud compute infrastructure), T1562.008 (disable or modify cloud logs). |

## Before enabling

1. Bastion is bootstrapped and `bastion_identities` is set (Bastion's `docs/SETUP.md`, step 2).
2. At least one Bastion control is in Deny (Bastion Phase 6). In Audit nothing is denied.
3. Verify in lab: `OperationNameValue`, `CategoryValue == "Policy"`, the `Properties_d.policies`
   layout, and that `Claims_d` carries the caller's object ID on denial rows.

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
