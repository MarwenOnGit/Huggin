# `uai-attached-to-host`

**Status: draft, not yet validated.** Tier: `beyond-fenrir`. Validation: `manual`.

**Fenrir does not trigger this rule.** It covers the next step an operator would take after Fenrir reports the opportunity.

Fenrir operations: none (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a user-assigned identity newly attached to a compute host (VM, scale set, site, container group, workflow, Automation Account), outside trusted automation. **Fenrir:** never does this. `core/enumerate/verdict.py` reports `UAI_ASSIGN_ROLES` as an opportunity. Lab replay: `az vm identity assign --identities <uai>` on a lab VM.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Azure Policy assigning a monitoring identity to many hosts: watchlist the policy identity. Terraform / Bicep creating new hosts: new hosts have no history, so they match; downgrade via deployment context or watchlist the pipeline. |
| False negatives | Writes where `requestbody` is missing or truncated. System-assigned identity enabled on a host (no UAI ID in the body): add a branch for `"type":"systemassigned"` changes. Identities attached at creation by a trusted but compromised pipeline. |
| Severity / MITRE | High for interactive users. T1098 (judgement call). |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
