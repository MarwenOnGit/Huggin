# Fenrir to Huggin coverage matrix

Operation IDs come from [FENRIR-OPERATIONS.md](FENRIR-OPERATIONS.md). Rules are described in
[RULE-PROPOSALS.md](RULE-PROPOSALS.md). Rules marked *(new)* are proposed in this review and
are not in the original Huggin list.

"Blind spot" = yes means no Sentinel table records the operation in a default setup.
"Validated" stays "no" until each rule has passed a benign replay in the lab. "Yes" cites the replay runs.

## Matrix

| Command | Op ID | Operation | Log source | Huggin rule | Blind spot | Validated |
|---|---|---|---|---|---|---|
| login | A-02 | Device code sign-in, Azure CLI client ID | `SigninLogs` | `devicecode-azure-mgmt-signin` *(new)*, context for `fenrir-chain` | no | no |
| login | A-04 | ROPC sign-in (`--auth-flow ropc`) | `SigninLogs` | `devicecode-azure-mgmt-signin` *(new)* (ROPC branch) | no | no |
| all | A-05 | Silent ARM / Graph token from refresh token | `AADNonInteractiveUserSignInLogs` | context only | no | no |
| enumerate | E-01 to E-07 | Graph directory reads (`/me`, `/domains`, directory role assignments, PIM eligibility, group membership, owned objects, managed devices) | `MicrosoftGraphActivityLogs` (P1/P2 + diagnostic setting) | `graph-directory-recon` *(new)* | yes, if Graph activity logs are not enabled | no |
| enumerate | E-08 to E-13 | ARM reads: management groups, subscriptions, RGs, resources, role assignments per scope | none | none possible in Sentinel | **yes** | n/a |
| enumerate, exploit | E-14 to E-27, X-05 | ARM reads in interesting RGs: identities, VMs, sites, SCM auth policy, plans, container groups, Logic Apps, Automation Accounts, effective permissions, resource properties | none | none possible in Sentinel | **yes** | n/a |
| exploit | X-01 to X-04 | ARM discovery reads, including `GET /me` once per RG | none | none possible in Sentinel | **yes** | n/a |
| exploit | X-06 | Graph `GET /servicePrincipals?$top=999` (whole tenant) | `MicrosoftGraphActivityLogs` | `graph-directory-recon` *(new)* | yes, if Graph activity logs are not enabled | no |
| exploit | X-07 | RBAC permission preflight (`.../Microsoft.Authorization/permissions`) | none | none possible in Sentinel | **yes** | n/a |
| exploit | X-08 | VM Run Command | `AzureActivity` | `vm-runcommand-by-user`, `fenrir-chain` | no | **yes**, 2026-11-03 (`vm-runcommand-by-user`; `fenrir-chain` multi-stage), replays 41728291675, 41734608159 |
| exploit | X-08 (host side) | Identity token issued on the VM | `AADManagedIdentitySignInLogs` | `mi-signin-anomaly`, `fenrir-chain` | no | no |
| exploit | X-09 | Run Command status polling | none | none | **yes** | n/a |
| exploit | X-10 | App Service publishing credentials list | `AzureActivity` | `appservice-publish-creds`, `fenrir-chain` | no | no |
| exploit | X-11 | Kudu `/api/command` with Basic auth | `AppServiceAuditLogs` / `AppServiceHTTPLogs` (verify in lab) | `appservice-publish-creds` (optional join) | yes, unless App Service diagnostic settings are on | no |
| exploit | X-11 (host side) | Identity token issued on the App Service | `AADManagedIdentitySignInLogs` | `mi-signin-anomaly` | no | no |
| exploit | X-12 | List Logic App triggers | none | none | **yes** | n/a |
| exploit | X-13 | Logic App `listCallbackUrl` | `AzureActivity` | `logicapp-callback-listed`, `fenrir-chain` | no | **yes**, 2026-11-03 (`logicapp-callback-listed`; `fenrir-chain` multi-stage), replays 41728291675, 41734608159 |
| exploit | X-14 | Container Instances exec | `AzureActivity` | `aci-exec`, `fenrir-chain` | no (session content: yes) | no |
| exploit | X-15 to X-18 | Automation: list runbooks, **read runbook source**, list variables, list credentials | none | none possible in Sentinel. `automation-runbook-run` does **not** fire, because Fenrir starts no job. | **yes** | n/a |
| exploit | X-19 to X-21 | ARM reads **as the managed identity from the operator's IP** | none | none possible in Sentinel | **yes** | n/a |
| post-exploit | P-01 to P-11 | ARM reads as the managed identity (subscriptions, RGs, resources, permissions, role assignments, storage accounts, registries) | none | none possible in Sentinel | **yes** | n/a |
| post-exploit | P-12 | Storage `listKeys` as the managed identity (`--dump-blobs`, also with `--dry-run`) | `AzureActivity` | `storage-keys-listed`, `mi-control-plane-new-ip` *(new)*, `fenrir-chain` | no | **partly**, 2026-11-03: `storage-keys-listed` branch C and `fenrir-chain` multi-stage, replays 41728291675, 41734608159. Branch A and `mi-control-plane-new-ip` (the managed-identity case Fenrir actually produces) need the purple-team run. |
| post-exploit | P-13 | ACR `listCredentials` as the managed identity (`--dump-images`, also with `--dry-run`) | `AzureActivity` | `acr-admin-creds-listed` *(new)*, `mi-control-plane-new-ip` *(new)*, `fenrir-chain` | no | no |
| post-exploit | D-01, D-02 | Blob / file listing and download with an account key or OAuth | `StorageBlobLogs`, `StorageFileLogs` (diagnostic settings) | out of scope for this review (candidate follow-up) | yes, unless storage diagnostics are on | no |
| post-exploit | D-03 | ACR token exchange, catalog, image pull | `ContainerRegistryLoginEvents`, `ContainerRegistryRepositoryEvents` | out of scope for this review (candidate follow-up) | yes, unless registry diagnostics are on | no |

## Blind spots

No rule can close these with the data Huggin collects. They are part of the design, not gaps to hide.

| What | Fenrir ops | Why it is invisible | What would help |
|---|---|---|---|
| ARM reads | E-08 to E-27, X-01 to X-05, X-07, X-09, X-12, X-19 to X-21, P-01 to P-11 | `AzureActivity` records writes and actions, never GETs. `enumerate` alone, and `post-exploit` without dump flags, leave no row. | Nothing in Sentinel today; hunting on the actions that follow |
| Automation Account path | X-15 to X-18 | Reading runbook source, variables and credential names are GETs | Nothing in `AzureActivity`; restrict who can read runbooks |
| Graph reconnaissance | E-01 to E-07, X-06 | Needs `MicrosoftGraphActivityLogs` (Entra ID P1/P2 and a diagnostic setting); this tenant has no P1/P2 | `graph-directory-recon` once licensed |
| What runs on a host | after X-08, X-11, X-14 | Control-plane logs show that a command ran, not what it did; the Run Command text is not logged (lab evidence X-08) | Host telemetry (Defender for Servers, AMA), Defender XDR |
| Data-plane access | D-01 to D-03 | Blob, file and registry access need per-resource diagnostic settings | `StorageBlobLogs`, `ContainerRegistry*` rules (roadmap) |

## Rules that Fenrir does not trigger

These rules are still worth building, because they cover the next step an operator would take
after Fenrir reports an opportunity. Fenrir will not produce a true positive for them, so each
needs its own lab replay.

| Huggin rule | Why Fenrir does not trigger it | Where Fenrir points at it |
|---|---|---|
| `rbac-self-assignment` | No PUT to `roleAssignments` anywhere in the code | `core/enumerate/verdict.py`: `ROLE_ASSIGNMENT_WRITE_ROLES` is reported as an opportunity |
| `uai-attached-to-host` | No PUT/PATCH to any compute resource | `core/enumerate/verdict.py`: `UAI_ASSIGN_ROLES` is reported as an opportunity |
| `automation-runbook-run` | `exploit_automation_account` only reads (X-15 to X-18) | `resource_exploit.py:REQUIRED_ACTIONS` checks for `runbooks/draft/write`, but nothing writes |
| `bastion-policy-denial` | Fenrir makes no writes, and Azure Policy cannot block its POST actions | Bastion's [PREVENT-DETECT.md](https://github.com/MarwenOnGit/Bastion/blob/main/docs/PREVENT-DETECT.md) hands this rule to Huggin |

## Coverage summary

| | Count |
|---|---|
| Inventory IDs | 66: 5 auth (A), 27 enumerate (E), 21 exploit (X, including the non-ARM X-11), 13 post-exploit (P) |
| Operations visible in `AzureActivity` | 6 (X-08, X-10, X-13, X-14, P-12, P-13) |
| Operations visible in `AuditLogs` | 0 |
| Operations visible only with `MicrosoftGraphActivityLogs` | 8 (E-01 to E-07, X-06) |
| ARM reads with no Sentinel visibility | all the rest |
| Rules validated | 4 (2026-11-03): `logicapp-callback-listed`, `storage-keys-listed` (branch C), `fenrir-chain` (multi-stage), `vm-runcommand-by-user`. See [STATUS.md](STATUS.md). |
