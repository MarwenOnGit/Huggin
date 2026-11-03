# Manual purple-team run

A checklist for the operator, not for CI. The operator runs their own Fenrir against their own
lab and records what Huggin's identity-tier rules saw. This document names only Fenrir's
commands from its README; how to use Fenrir is in Fenrir's own documentation and legal notice.

## Scope and authorization

- Target: the operator's own Fenrir lab (`fenrir-lab-prod-rg`), in the operator's own tenant and
  subscription. Nothing else.
- Huggin's code and CI never touch that resource group; this run is the only place it is used.
- Write down the date, the operator, and the planned window before starting.

## Before the run

- [ ] The Fenrir lab VM is started on purpose for this run (and deallocated or deleted after).
- [ ] The managed identity on the lab host has **at least 7 days** of normal activity if
      `mi-signin-anomaly` is in scope, and some prior control-plane history if
      `mi-control-plane-new-ip` is in scope (both rules skip identities with no history).
- [ ] Rules to observe are deployed and enabled: add them to `enabled_rules` in
      `infra/sentinel/huginn.auto.tfvars.json` and apply with a reviewed plan. Typical set:
      `mi-control-plane-new-ip`, `fenrir-chain`, `storage-keys-listed`, `vm-runcommand-by-user`.
- [ ] For sign-in and Graph rules only: an Entra ID P1/P2 licence (for example a P2 trial),
      `enable_entra_logs = true` applied, and log data visible in `SigninLogs` and
      `AADManagedIdentitySignInLogs`. Without a licence, skip those rows below.
- [ ] Note the operator's public IP address (it should appear as `CallerIpAddress`).

## The run

Run Fenrir's commands in its normal order, recording the UTC start and end time of each:

| Step | Fenrir command | Start (UTC) | End (UTC) | Notes |
|---|---|---|---|---|
| 1 | `login` | | | |
| 2 | `enumerate` | | | Expected: nothing in `AzureActivity` (reads only) |
| 3 | `exploit` | | | |
| 4 | `post-exploit` with a dump flag (`--dump-blobs` or `--dump-images`) | | | P-12 / P-13 run as the managed identity |

## What to check in Sentinel

Wait at least 30 minutes after the last step. For each rule, record the result.

| Rule | Expected signal | Fired? | Time to alert | Incident ID | Notes |
|---|---|---|---|---|---|
| `vm-runcommand-by-user` | X-08 by the operator's user | | | | |
| `fenrir-chain` (multi-stage) | 2+ stages by the operator's user | | | | |
| `fenrir-chain` (identity pivot) | the managed identity acting from the operator's IP | | | | |
| `mi-control-plane-new-ip` | the managed identity, P-12/P-13 from a new IP | | | | |
| `storage-keys-listed` branch A | managed identity from a new IP, High | | | | |
| `devicecode-azure-mgmt-signin` | device code sign-in (licence needed) | | | | |
| `mi-signin-anomaly` | ARM token for an identity that never asked for one (licence needed) | | | | |
| `graph-directory-recon` | Graph reads during `enumerate` (licence needed) | | | | |

Also record, from `AzureActivity` (KQL in the rule READMEs):
- [ ] whether `Claims_d.xms_mirid` is present on the managed identity's rows (open item 2 in
      STATUS.md), and whether `Caller` is its object ID or client ID (item 3);
- [ ] that `enumerate` left no `AzureActivity` rows (blind spot confirmed).

## After the run

- [ ] Deallocate or delete the Fenrir lab VM (deallocated VMs still count against vCPU quota).
- [ ] Capture the evidence rows with `scripts/evidence/capture.py --since <start> --caller <id>`
      and check them for secrets before committing.
- [ ] Update `docs/STATUS.md`, the rule READMEs' validation logs, and the "Validated" column in
      `docs/FENRIR-MAPPING.md`, only for what was actually observed.
- [ ] Remove any rule from `enabled_rules` that should not stay deployed, with a reviewed plan.
