# ADR 0001: Detections as code

Date: 2026-11-03. Status: accepted.

## Context

Sentinel rules can be written in the portal, but portal rules have no review, no history and no
tests. Huginn has to show that each rule is tied to a Fenrir operation and was proven in a lab.

## Decision

Each rule is a folder `detections/<tier>/<rule-id>/` with:
- `rule.kql`: the query, starting with "Draft, not yet validated." until a lab run proves it;
- `rule.yaml`: metadata (tier, `fenrir_ops`, severity, frequency, lookback, MITRE, `validation`,
  `deployable`, `status`);
- `README.md`: what it detects, changes from the review draft, false positives and negatives,
  and a validation log;
- `replay.sh`: the benign replay, only for `validation: ci`.

Terraform creates rules with `fileset` and `for_each` over `detections/**/rule.yaml`, so adding a
rule never needs Terraform edits. `tests/test_rules_static.py` checks every folder on every push.

## Consequences

- Rule changes are reviewed as diffs and tied to commits.
- The folder layout encodes the tier, and the static tests enforce the tier rules (for example,
  licence-gated rules cannot be marked deployable).
- Portal edits to a rule are overwritten by the next apply. That is intended.
