# Architecture decision records

| ADR | Decision |
|---|---|
| [0001](0001-detections-as-code.md) | Detections as code: one folder per rule, deployed by `for_each` over `rule.yaml` |
| [0002](0002-terraform-over-bicep.md) | Terraform rather than Bicep |
| [0003](0003-oidc-identities-and-state.md) | OIDC instead of secrets; deploy and lab-attacker identities; bootstrap and state; GitHub ID-based subjects |
| [0004](0004-accepted-iac-findings.md) | Accepted tflint and checkov findings |
| [0005](0005-replays-fresh-resources-and-dedup.md) | Benign replays instead of Fenrir in CI; fresh resources per run (baseline trap); ingestion-time deduplication; 47-hour baselines; drift check instead of apply |
| [0006](0006-licence-tiers.md) | Licence tiers |
| [0007](0007-watchlist-not-client-app-exclusions.md) | Watchlist exclusions by identity, never by client app |
| [0008](0008-purple-environment.md) | A disposable, fully logged purple-team environment (`infra/purple`): every log source on, canary secrets, capture from every table |
