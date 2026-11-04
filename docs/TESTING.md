# Testing

Nothing is "validated" until a replay produced the expected Sentinel alert, recorded with a date
in [STATUS.md](STATUS.md).

## Layers

| Layer | Where | Azure | What it proves |
|---|---|---|---|
| Static | `make test` (`tests/test_rules_static.py`) | no | Every rule folder is complete; `rule.yaml` is valid; `fenrir_ops` exist; CI rules have `replay.sh`; licence-gated tables stay out of deployable rules; entity and alert-name columns exist in the query; the KQL `Frequency` equals the rule frequency |
| KQL syntax | `make kql` (`tests/kql_check`, Microsoft's `Kusto.Language` parser) | no | Every `rule.kql` and `functions/*.kql` parses, and every deliberately broken query in `tests/kql_check/fixtures/broken` is rejected (self-test, `--expect-errors`). Syntax only: names are not resolved against the workspace schema, so a misspelled column still passes; the replays catch those |
| IaC | `make lint` | no | `terraform fmt`, `validate`, tflint, checkov (also with every opt-in lab resource on) |
| Lab evidence | `.github/workflows/evidence.yml` + `scripts/evidence/capture.py` | yes | What the real `AzureActivity` rows look like (Phase 3) |
| Replay | `.github/workflows/replay.yml` | yes | Benign actions as the lab attacker raise the expected alerts |
| Purple team | `docs/PURPLE-TEAM.md` (manual) | yes | Identity-tier rules against a real Fenrir run |

## Every push (`ci.yml`)

No Azure login and no secrets. Five parallel jobs: static rule tests (plus `py_compile`,
`bash -n`, shellcheck at error level), KQL syntax, `terraform fmt` and `validate` (no backend),
tflint, checkov. `make ci` runs the same checks locally (`make kql` needs the .NET SDK).

Breaking a rule turns it red, for example:
- `let Frequency = 10m;` in a rule whose `rule.yaml` says `PT5M` (static test: dedup window);
- `lookback: P3D` with `frequency: PT5M` (static test: Sentinel rejects it);
- a missing `|` or bracket in a query (KQL syntax job);
- an entity mapped to a column the query does not output (static test).

## The replay loop (`replay.yml`)

1. **drift** (deploy identity): `terraform plan` of `infra/sentinel` and `infra/lab` must show no
   changes, so the rules in Sentinel are the rules in git. The workflow never applies.
2. **replay** (lab attacker, `lab-replay` environment): `scripts/replay/run.sh` runs each rule's
   `replay.sh`. Every replay creates a fresh resource, performs one benign action with the
   response sent to `/dev/null`, and deletes the resource through a `trap`.
3. **cleanup** (lab attacker, always): deletes anything in `huginn-lab-rg` tagged `huginn-replay`.
4. **validate** (deploy identity): `tests/validate_alert.py` polls `SecurityAlert` until each rule
   has an alert after the replay start whose entities contain the lab attacker's object ID.
   It reports time-to-alert and fails after the timeout (default 30 minutes).

Run it by hand: Actions, `replay`, Run workflow. It is also scheduled nightly at 02:30 UTC; GitHub
runs scheduled workflows on a best-effort basis, and the first nightly run started at 09:32 UTC.

## The baseline trap

`logicapp-callback-listed` and branch C of `storage-keys-listed` alert only on a **new
(caller, resource) pair** in the baseline window (47 hours in the deployed rules; see below). If every nightly replay used the same lab attacker on the
same Logic App or storage account, the pair would be "known" after the first run, the rule would
correctly stay silent, and the build would go red for the wrong reason.

**Fix by design:** each replay creates a fresh, uniquely named resource
(`logic-huginn-replay-<run id>`, `sthgr<run id>`), acts on it once and deletes it. The pair is new
on every run. `fenrir-chain` has no baseline; it fires because one caller performs two stages.

**Test of the fix:** run `replay.yml` twice in a row. Both runs must be green. **Passed on
2026-11-03:** runs 41728291675 and 41734608159, same lab attacker, every rule fired in both, one
alert per event.

## Duplicate alerts and ingestion delay

Rules run every 5 minutes, but `AzureActivity` rows arrive 3 to 4.5 minutes after the action
(lab evidence, 2026-11-03). A query filtered only on `TimeGenerated` over the last hour would
either miss late rows (short window) or alert up to 12 times on the same row (long window).

Huggin's rules select "new" rows with `ingestion_time() > ago(Frequency) and ingestion_time() <= now()`,
where `Frequency` equals the rule frequency. Baselines use the rows ingested before the current
interval. The static test checks that the KQL `Frequency` matches `rule.yaml`.

**Why the upper bound (found 2026-11-03).** Inside a scheduled rule, `now()` is the window end
(`Query End Time UTC` in the alert), but Sentinel runs the query about 5 minutes later. Without
`<= now()`, a row ingested in that gap is "new" in two runs. The first deployed version, which
followed Microsoft's sample (`ingestion_time() > ago(lookback)` only), raised 2 alerts per event for
rules 1 and 2 and 3 for `fenrir-chain` on the first green replay.

**Per request, not per row.** One request writes several rows (Start, Accept, Success) that can
be ingested minutes apart (X-08: 2.5 minutes). Rules that aggregate (`vm-runcommand-by-user`,
`fenrir-chain`) treat a `CorrelationId` as new once, when its first row lands. Rules with a "new
pair" baseline are already safe: the first row's pair is in the baseline for the next run.

**How it was checked.** A read-only simulation: each rule is run ad hoc with
`now()` and `ago()` pinned to Sentinel's real window ends and `TimeGenerated` limited to the
window. The simulation reproduced the deployed rules' real alert times exactly, then showed one
alert per event for the fixed rules.

Known limit: if a scheduled run is skipped or delayed by more than its interval, rows ingested in
the gap are never evaluated. Sentinel reports skipped runs in `SentinelHealth`, if health
monitoring is turned on.

## Frequency versus baseline length

The Sentinel API rejects a scheduled rule whose query period is 2 days or more unless it runs at
most once an hour (found by a failed apply on 2026-11-03; the provider does not check it, and the
documentation page read earlier did not mention it). `tests/test_rules_static.py` now enforces it.

For the two "new pair" demo rules Huggin chose speed: frequency `PT5M`, lookback `PT47H`,
KQL `Baseline = 47h`. The cost is a shorter memory: a caller who touches the same resource every
3 or more days is "new" each time. Rules that are not time-critical (`acr-admin-creds-listed`,
`mi-control-plane-new-ip`) keep 14 days and run hourly. A long baseline at 5-minute speed is on
the roadmap (ADR 0005, option C).

## Expected time to alert

Ingestion + wait for the next window end (up to 5 min) + Sentinel's 5-minute run delay + alert write.

| Rule | Ingestion seen in the lab | Measured time to alert |
|---|---|---|
| `fenrir-chain` | 3 to 4.5 min | 5 min 5 s; 7 min 24 s |
| `logicapp-callback-listed` | 3 to 4.5 min (8 min on 2026-11-03 21:21) | 10 min 24 s |
| `storage-keys-listed` | 3 to 4.5 min (5.7 min on 2026-11-03 21:22) | 10 min 35 s |
| `vm-runcommand-by-user` | 7 to 10 min | not yet measured; expect 15 to 20 min |

The validation timeout is 30 minutes.

## Expected run time of `replay.yml`

| Job | Time |
|---|---|
| drift (two `terraform plan`) | about 1 to 2 min |
| replay: Logic App and storage account | under 1 min |
| replay: X-08 VM (create, Run Command, delete) | about 2 to 3 min (evidence run 2026-11-03: 82 s, but VM creation varies) |
| validate | until the last alert, up to 30 min |
| cleanup | under 1 min |

A full run with X-08 should finish in about 20 to 25 minutes.
