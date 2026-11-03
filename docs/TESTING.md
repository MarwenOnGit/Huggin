# Testing

Nothing is "validated" until a replay produced the expected Sentinel alert, recorded with a date
in [STATUS.md](STATUS.md).

## Layers

| Layer | Where | Azure | What it proves |
|---|---|---|---|
| Static | `make test` (`tests/test_rules_static.py`) | no | Every rule folder is complete; `rule.yaml` is valid; `fenrir_ops` exist; CI rules have `replay.sh`; licence-gated tables stay out of deployable rules; entity and alert-name columns exist in the query; the KQL `Frequency` equals the rule frequency |
| IaC | `make lint` | no | `terraform fmt`, `validate`, tflint, checkov |
| Lab evidence | `.github/workflows/evidence.yml` + `scripts/evidence/capture.py` | yes | What the real `AzureActivity` rows look like (Phase 3) |
| Replay | `.github/workflows/replay.yml` | yes | Benign actions as the lab attacker raise the expected alerts |
| Purple team | `docs/PURPLE-TEAM.md` (manual) | yes | Identity-tier rules against a real Fenrir run |

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

Run it by hand: Actions, `replay`, Run workflow. It also runs nightly at 02:30 UTC.

## The baseline trap

`logicapp-callback-listed` and branch C of `storage-keys-listed` alert only on a **new
(caller, resource) pair** in the baseline window (47 hours in the deployed rules; see below). If every nightly replay used the same lab attacker on the
same Logic App or storage account, the pair would be "known" after the first run, the rule would
correctly stay silent, and the build would go red for the wrong reason.

**Fix by design:** each replay creates a fresh, uniquely named resource
(`logic-huginn-replay-<run id>`, `sthgr<run id>`), acts on it once and deletes it. The pair is new
on every run. `fenrir-chain` has no baseline; it fires because one caller performs two stages.

**Test of the fix:** run `replay.yml` twice in a row. Both runs must be green. (Not yet done:
see STATUS.md.)

## Duplicate alerts and ingestion delay

Rules run every 5 minutes, but `AzureActivity` rows arrive 3 to 4.5 minutes after the action
(lab evidence, 2026-11-03). A query filtered only on `TimeGenerated` over the last hour would
either miss late rows (short window) or alert up to 12 times on the same row (long window).

Huginn's rules select "new" rows with `ingestion_time() > ago(Frequency)`, where `Frequency`
equals the rule frequency, as in Microsoft's guidance on ingestion delay. Consecutive runs cover
consecutive ingestion intervals, so each row is processed once. Baselines use the rows ingested
before the current interval. The static test checks that the KQL `Frequency` matches `rule.yaml`.

Known limit: if a scheduled run is skipped or delayed by more than its interval, rows ingested in
the gap are never evaluated. Sentinel reports skipped runs in `SentinelHealth`, if health
monitoring is turned on.

## Frequency versus baseline length

The Sentinel API rejects a scheduled rule whose query period is 2 days or more unless it runs at
most once an hour (found by a failed apply on 2026-11-03; the provider does not check it, and the
documentation page read earlier did not mention it). `tests/test_rules_static.py` now enforces it.

For the two "new pair" demo rules Huginn chose speed: frequency `PT5M`, lookback `PT47H`,
KQL `Baseline = 47h`. The cost is a shorter memory: a caller who touches the same resource every
3 or more days is "new" each time. Rules that are not time-critical (`acr-admin-creds-listed`,
`mi-control-plane-new-ip`) keep 14 days and run hourly. A long baseline at 5-minute speed is on
the roadmap (ADR 0005, option C).

## Expected time to alert

Ingestion (3 to 4.5 min) + wait for the next run (up to 5 min) + Sentinel's 5-minute delay +
alert write: roughly 10 to 15 minutes. The validation timeout is 30 minutes. Measured values go
into STATUS.md after each run.
