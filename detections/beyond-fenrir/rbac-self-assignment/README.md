# `rbac-self-assignment`

**Status: draft, not yet validated.** Tier: `beyond-fenrir`. Validation: `manual`.

**Fenrir does not trigger this rule.** It covers the next step an operator would take after Fenrir reports the opportunity.

Fenrir operations: none (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a principal creating a role assignment for itself, outside PIM. **Fenrir:** never does this. `core/enumerate/verdict.py` reports `ROLE_ASSIGNMENT_WRITE_ROLES` as an opportunity. Lab replay: `az role assignment create --assignee <your own object ID>`.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | PIM activations (excluded by `appid`). Owners who intentionally add themselves a narrower role: rare, triage. |
| False negatives | Granting a role to a **group** the caller belongs to, or to a second account or service principal the caller controls. Assignments where `requestbody` is not logged. Add a companion rule for "user grants a privileged role to a principal created in the last 24 hours". |
| Severity / MITRE | High for privileged roles. T1098.003. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
