# Five-minute demo (interview, 11 November 2026)

Goal: show that every logged step of Fenrir is detected, that this is proven by an automated
test, and that the blind spots are known.

## Before the interview

- [ ] The nightly `replay` run of the day is green (Actions tab). If not, run it by hand early
      (about 20 to 25 minutes).
- [ ] Sentinel incidents from that run are visible (Microsoft Sentinel > Incidents, filter
      "Huginn").
- [ ] A throwaway branch is ready for the broken-rule step (see step 5); `main` is untouched.
- [ ] Tabs open: README, FENRIR-MAPPING.md, one rule folder, the last green `replay` run,
      Sentinel incidents, the CI run list.

## Script

| Time | Show | Say |
|---|---|---|
| 0:00 | [README](../README.md) diagram | "Fenrir is my Azure attack tool; Huggin is its defensive twin. Fenrir makes no writes. Its only logged footprint is six POST actions. Huggin turns each into a Sentinel rule and proves it with a benign replay every night." |
| 0:45 | [FENRIR-MAPPING.md](FENRIR-MAPPING.md) | "Every Fenrir operation, the log table it lands in, the rule that covers it, and whether it is validated. Four are validated with run IDs. The rest are honest drafts." |
| 1:30 | `detections/core/logicapp-callback-listed/` | `rule.kql` (new caller-workflow pair in 47 hours, ingestion-time dedup), `rule.yaml` (MITRE T1552, frequency, lookback), `replay.sh` (fresh Logic App per run, output discarded), README validation log. |
| 2:15 | Last green `replay` run | Four jobs: drift check, replay as the lab attacker, cleanup, validation table with time to alert per rule. |
| 2:45 | Sentinel incident | Alert title with the caller, Account and AzureResource entities, severity from the query. |
| 3:15 | Broken rule on the throwaway branch | Change `let Frequency = 5m;` to `10m` in one rule, push, show `ci.yml` red on the static test. Optionally remove a `\|` to show the KQL parser annotation. |
| 4:00 | Blind spots ([README](../README.md#what-huggin-can-and-cannot-see)) | "Reads are not logged, so Fenrir's enumeration is invisible to any rule. Graph recon needs P1/P2. What runs on the host is not in control-plane logs. Knowing this is part of the design." |
| 4:30 | Roadmap | 14-day baselines at 5-minute speed, playbooks, data-plane logs, Defender XDR. |

## Short answers

**Why not exclude the Azure CLI client ID?** Fenrir signs in with the Azure CLI's own public
client ID by default, so it is identical to a normal `az login`. Excluding the CLI would exclude
the attacker. Huggin excludes identities, not tools: a watchlist of (principal, scope, operation)
triples with an owner and an expiry date (ADR 0007).

**How are false positives handled?** Three layers. The watchlist covers known automation
(Huggin's own deployment principal, whose Terraform refresh calls `listKeys` and
`listCallbackUrl`). "New pair" baselines silence repeat behaviour: a developer opening their own
Logic App every day stops alerting. Deployment context lowers severity instead of dropping the
event. A real example: my own local Terraform refresh hit the storage rule on day one; I fixed it
with a narrow watchlist entry (two operations, Huggin resource groups, 90-day expiry), not by
weakening the query.

**How do you avoid duplicate alerts?** Rows are "new" when ingested in `(now() - 5m, now()]`.
The first version alerted 2 to 3 times per event because, inside a scheduled rule, `now()` is the
window end while the query runs 5 minutes later. I found it by decoding the alerted rows, fixed
it, and proved the fix with a simulation pinned to Sentinel's real window ends before deploying.

**What does it cost?** About zero always on: Activity log ingestion is free, there is no
always-on compute, and the nightly VM lives about 3 minutes. Workspace cap 0.5 GB/day.

**Why benign replays and not Fenrir in CI?** Running Fenrir in CI would mean stealing
managed-identity tokens on a schedule. The replays perform the same ARM operations with the same
API versions as a dedicated lab identity, on fresh resources. Fenrir itself is for the manual
purple-team run.

**What would Defender XDR and playbooks add?** Defender XDR would correlate these alerts with
endpoint and identity signals (for example the host-side activity Huggin cannot see) into one
incident. A Logic Apps playbook could act on `storage-keys-listed`: rotate the listed key, notify
the owner, and tag the incident, cutting the time a stolen key stays useful.

**Why a 47-hour baseline?** Sentinel requires hourly runs when the lookback is 2 days or more.
I chose 5-minute alerts with a 47-hour memory over hourly alerts with 14 days, and documented a
design (a known-pairs watchlist refreshed daily) that gives both.
