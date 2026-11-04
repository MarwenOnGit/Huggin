# Manual purple-team run

A checklist for the operator, not for CI. The operator runs their own Fenrir against a
disposable, fully logged environment (`infra/purple`, [ADR 0008](adr/0008-purple-environment.md)),
captures **everything** the run left in the workspace, and records what Huggin's rules saw. This
document names only Fenrir's commands from its README; how to use Fenrir is in Fenrir's own
documentation and legal notice.

## Scope and authorization

- Target: `huginn-purple-rg`, created by `infra/purple` in the operator's own tenant and
  subscription for this run, and destroyed after it. Nothing else.
- Attacker: a **dedicated, low-privilege** Entra user, Contributor on `huginn-purple-rg` only
  (`attacker_object_id`). Fenrir acts on every resource group its identity can see: never run it
  as the operator's own account, which is Owner of the subscription.
- `fenrir-lab-prod-rg` stays out of bounds for Huggin's code and CI. A run against it is still
  possible by hand; the steps below then apply without the `infra/purple` parts.
- Write down the date, the operator, and the planned window before starting.

## Before the run

- [ ] Quota: the purple VM needs 2 vCPU in the region (docs/STATUS.md). Delete, do not just
      deallocate, any VM you do not need.
- [ ] Only one Free (F1) App Service plan per region on some offers: `enable_appservice = false`
      in `infra/lab` (the default), or set `enable_webapp = false` here.
- [ ] Raise the workspace cap for the run window (`daily_quota_gb` in `infra/sentinel`, for
      example 2), or ingestion may stop mid-run. Set it back afterwards.
- [ ] Optional, identity tier: an Entra ID P2 trial, then `enable_entra_logs = true` in
      `infra/sentinel` (a Global or Security Administrator applies it). Without it, sign-in and
      Graph tables stay empty and the identity rows below are skipped.
- [ ] Optional: `enable_defender_arm = true` here, to test whether Defender for Resource Manager
      sees Fenrir's reads. Subscription-wide and paid after its trial; turn it off afterwards.
- [ ] Rules to observe are deployed and enabled (`enabled_rules` in
      `infra/sentinel/huginn.auto.tfvars.json`, reviewed plan). Typical set:
      `mi-control-plane-new-ip`, `fenrir-chain`, `storage-keys-listed`, `vm-runcommand-by-user`,
      and the drafts the run can validate (`appservice-publish-creds`, `aci-exec`,
      `acr-admin-creds-listed`).
- [ ] Create the environment:

```bash
make init STACK=purple
```

```bash
terraform -chdir=infra/purple plan -out=tfplan -var attacker_object_id=<attacker object id> -var run_label=<date>
```

```bash
make apply STACK=purple
```

- [ ] Wait about 15 minutes (diagnostic settings, the Azure Monitor Agent and role assignments
      take time to start), then prove the environment logs **before** spending a Fenrir run on it:

```bash
make purple-preflight
```

      It checks that every diagnostic setting exists and sends to `law-huginn`, reads the Key
      Vault canary and lists the canary blob as the operator (responses discarded), and shows the
      rows that reached the workspace per table and resource. Do not start Fenrir until it says
      `READY`. Data-plane rows take 5 to 15 minutes: re-run with
      `python3 scripts/purple/preflight.py --no-poke` if it is short. Logic App, Automation, web
      app and registry log only when used, so they show no data until the run.
- [ ] `mi-signin-anomaly` and `mi-control-plane-new-ip` skip identities with no history. If they
      are in scope, keep the environment up for 7 days first (about 2 to 3 USD; docs/COST.md).
- [ ] Note the attacker's public IP address (it should appear as `CallerIpAddress`).

## The run

Sign in to Fenrir as the attacker user. Run its commands in its normal order, recording the UTC
start and end time of each:

| Step | Fenrir command | Start (UTC) | End (UTC) | Notes |
|---|---|---|---|---|
| 1 | `login` | | | |
| 2 | `enumerate` | | | Expected: nothing in `AzureActivity` (reads only). Check every other table. |
| 3 | `exploit` | | | |
| 4 | `post-exploit` with a dump flag (`--dump-blobs` or `--dump-images`) | | | P-12 / P-13 as the managed identity, D-01 / D-03 data plane |

## Capture everything

Wait at least 30 minutes after the last step, then:

```bash
make purple-capture SINCE=<start of step 1> UNTIL=<end of step 4 + 30 min> LABEL=<date> IND=<attacker object id>,<attacker IP>
```

The managed identity's IDs, the VM identity and the canary prefix are added from the stack's
outputs. The script writes, under `lab-evidence/purple/<date>/`:
- `SUMMARY.md`: every table in the window, all rows against rows that match the run;
- one redacted JSON file per table with matching rows (the attacker IP becomes
  `INDICATOR_IP_n`; canary values, keys and tokens are redacted);
- a **canary check**: every table that contains a canary value. A canary in a log means a stolen
  secret reached that log.

Raw copies stay in `lab-evidence/raw/` (git-ignored). Review the redacted files before
committing them.

## What to check in Sentinel

For each rule, record the result.

| Rule | Expected signal | Fired? | Time to alert | Incident ID | Notes |
|---|---|---|---|---|---|
| `vm-runcommand-by-user` | X-08 by the attacker user | | | | |
| `appservice-publish-creds` | X-10 | | | | |
| `aci-exec` | X-14 | | | | |
| `acr-admin-creds-listed` | P-13 | | | | |
| `fenrir-chain` (multi-stage) | 2+ stages by the attacker user | | | | |
| `fenrir-chain` (identity pivot) | the managed identity acting from the attacker's IP | | | | |
| `mi-control-plane-new-ip` | the managed identity, P-12/P-13 from a new IP | | | | |
| `storage-keys-listed` branch A | managed identity from a new IP, High | | | | |
| `devicecode-azure-mgmt-signin` | device code sign-in (licence needed) | | | | |
| `mi-signin-anomaly` | ARM token for an identity that never asked for one (licence needed) | | | | |
| `graph-directory-recon` | Graph reads during `enumerate` (licence needed) | | | | |

And from the capture:
- [ ] whether `Claims_d.xms_mirid` is present on the managed identity's `AzureActivity` rows
      (open item 2 in STATUS.md), and whether `Caller` is its object ID or client ID (item 3);
- [ ] every blind spot in [FENRIR-MAPPING.md](FENRIR-MAPPING.md): did `enumerate`, X-09, X-12,
      X-15 to X-18 and P-01 to P-11 leave rows in **any** table? With Defender for Resource
      Manager on, did it raise anything?
- [ ] what `Syslog` shows on the VM during X-08 (is the Run Command visible on the host?);
- [ ] which data-plane tables recorded D-01 (`StorageBlobLogs`) and D-03 (`ContainerRegistry*`),
      and with which authentication type;
- [ ] the canary check.

## After the run

- [ ] Destroy the environment the same day (`make purple-destroy`). Every canary is then gone;
      Fenrir's local output still holds them, so delete that too.
- [ ] Set `daily_quota_gb`, `enable_entra_logs` and `enable_defender_arm` back if you changed them.
- [ ] Update `docs/STATUS.md`, the rule READMEs' validation logs, the "Validated" and "Blind spot"
      columns in `docs/FENRIR-MAPPING.md`, only for what was actually observed, citing
      `lab-evidence/purple/<date>/`.
- [ ] New telemetry found? Each signal goes through the normal pipeline: evidence, rule,
      benign `replay.sh`, two green replays (docs/TESTING.md).
- [ ] Remove any rule from `enabled_rules` that should not stay deployed, with a reviewed plan.
