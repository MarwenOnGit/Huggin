# Huginn

**Fenrir attacks Azure managed identities; Huginn proves Sentinel catches each logged step.**

Huginn is the defensive counterpart to [Fenrir](https://github.com/MarwenOnGit/fenrir): Microsoft
Sentinel detection rules for the actions Fenrir performs, deployed with Terraform, and proven by
replaying benign versions of those actions in a lab subscription.

> **Status (2026-11-03): work in progress. No rule is validated yet.** Every query is a draft
> until a lab run proves it. See [docs/STATUS.md](docs/STATUS.md) for the honest, dated state.

## What Huginn can and cannot see

Fenrir makes no writes. Its whole `AzureActivity` footprint is six POST actions: VM Run Command
(X-08), App Service publishing credentials (X-10), Logic App callback URL (X-13), Container
Instances exec (X-14), storage `listKeys` (P-12) and ACR `listCredentials` (P-13). Everything else
is an ARM read, and `AzureActivity` does not record reads.

**Blind spots**
- ARM reads never reach `AzureActivity`, so Fenrir's `enumerate` phase and the Automation Account
  path (X-15 to X-18: reading runbook source and variables) leave no trace.
- Graph recon (E-01 to E-07, X-06) is visible only with Entra ID P1/P2 and
  `MicrosoftGraphActivityLogs`.
- What happens on a host after Run Command or exec is not in control-plane logs.

## Rules by tier

| Tier | Rules | Needs | Validation |
|---|---|---|---|
| Core | `logicapp-callback-listed`, `storage-keys-listed`, `fenrir-chain`, `vm-runcommand-by-user`, `appservice-publish-creds`, `aci-exec`, `acr-admin-creds-listed` | `AzureActivity` only, no Entra licence | Benign replays in CI |
| Identity | `mi-control-plane-new-ip`, `mi-signin-anomaly`, `devicecode-azure-mgmt-signin`, `graph-directory-recon` | Mostly Entra ID P1/P2 | Manual purple-team run |
| Beyond Fenrir | `rbac-self-assignment`, `uai-attached-to-host`, `automation-runbook-run` | `AzureActivity` | Manual replay. Next steps an operator would take after Fenrir reports the opportunity. |

The coverage matrix is [docs/FENRIR-MAPPING.md](docs/FENRIR-MAPPING.md).

## Layout

```
infra/bootstrap   remote state, GitHub OIDC app
infra/sentinel    workspace, Sentinel, connectors, watchlist, HuginnActivity function, rules
infra/lab         Fenrir-shaped target resources for benign replays
detections/       one folder per rule: rule.kql, rule.yaml, README.md, replay.sh (CI rules)
functions/        HuginnActivity.kql (shared normalisation)
watchlists/       HuginnTrustedAutomation.csv
tests/            static rule tests, alert validation
lab-evidence/     raw AzureActivity rows from lab runs, secrets redacted
docs/             review docs, status, design records
```

## Quick start (local, no Azure)

```bash
python3 -m pip install -r tests/requirements.txt
make test     # static checks on every rule folder
make lint     # terraform fmt, validate, tflint, checkov
```

Deployment, replay, cost and teardown instructions arrive with Phases 2 and 5.
