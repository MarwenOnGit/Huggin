# `automation-runbook-run`

**Status: draft, not yet validated.** Tier: `beyond-fenrir`. Validation: `manual`.

**Fenrir does not trigger this rule.** It covers the next step an operator would take after Fenrir reports the opportunity.

Fenrir operations: none (IDs from [FENRIR-OPERATIONS.md](../../../docs/FENRIR-OPERATIONS.md)).

## What it detects

**Detects:** a runbook job started by a caller who edited a runbook in the same account in the last 2 hours, or who has never started a job in that account in 14 days. **Fenrir:** only **reads** runbooks, runbook source, variables and credentials (X-15 to X-18). It never starts a job, so this rule will not fire on Fenrir. Those reads are a blind spot. Lab replay: edit a lab runbook, publish it, start it from the portal.

## Query

See [rule.kql](rule.kql). Source: the draft in [RULE-PROPOSALS.md](../../../docs/RULE-PROPOSALS.md). Changes from the draft are listed below.

## Changes from the draft

- None yet. Phase 3 lab evidence may change field names and status strings.

## False positives, false negatives, severity

| | |
|---|---|
| False positives | Runbook developers testing their own changes (edit then run): High is noisy for them; watchlist the automation team per account after the first week. Schedule and webhook starts: confirm in lab which `Caller` they show, then exclude that caller. |
| False negatives | Reading runbook source, variables and credentials (Fenrir's actual behaviour): no log. Webhook URLs used by an outsider (the job start comes from the service, not the attacker). Hybrid Runbook Worker activity on hosts. |
| Severity / MITRE | Medium, High for edit then run. T1651. |

## Validation

| Date | Run | Result | Time to alert | Evidence |
|---|---|---|---|---|
| | | not yet run | | |
