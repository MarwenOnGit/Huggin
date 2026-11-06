# ADR 0005: Benign replays on fresh resources, ingestion-time deduplication

Date: 2026-11-03. Status: accepted.

## Context

Huginn must prove in CI that each core rule fires on the action Fenrir performs. Running Fenrir
itself in CI would mean stealing managed-identity tokens on a schedule. Several rules alert only
on a new (caller, resource) pair over 14 days. Scheduled rules run every 5 minutes while
`AzureActivity` arrives 3 to 4.5 minutes late.

## Decisions

1. **Benign replays, not Fenrir.** CI performs the same ARM action Fenrir performs (same
   operation name and API version) as a dedicated lab attacker identity, on resources the replay
   creates, with responses discarded. CI never runs Fenrir and never requests a managed-identity
   token. Fenrir itself is used only in the manual purple-team run.
2. **Fresh resource per run.** Replays for "new pair" rules create a uniquely named resource
   and delete it afterwards, so the pair is new every night (the baseline trap, docs/TESTING.md).
3. **Ingestion-time deduplication.** Rules treat rows as new when `ingestion_time()` falls in
   `(now() - interval, now()]`, and build baselines from earlier rows. The upper bound matters:
   in a scheduled rule `now()` is the window end, while the query runs about 5 minutes later
   (corrected 2026-11-03 after the first deployment alerted 2 to 3 times per event). Aggregating
   rules count a request (`CorrelationId`) once, when its first row is ingested. Rule-level suppression was rejected:
   it hides every alert of the rule for the suppression period, including the second replay of the
   baseline-trap test. Alert grouping was rejected: it groups alerts into incidents but does not
   stop duplicate alerts.
4. **Short baseline for fast rules (added 2026-11-03).** The Sentinel API requires a frequency of
   at least 1 hour when the query period is 2 days or more. The two "new pair" demo rules run every
   5 minutes with a 47-hour baseline (`PT47H`) rather than hourly with 14 days. Options considered:

   | Option | Frequency / lookback | Time to alert | Detection cost |
   |---|---|---|---|
   | **A (chosen)** | PT5M / PT47H | about 10 to 15 min | Pairs are forgotten after about 2 days, so slow-cadence legitimate callers alert more often |
   | B | PT1H / P14D | up to about 70 min | None, but CI waits about 90 min and the demo cannot show a live alert |
   | C (roadmap) | PT5M rule reading a baseline kept elsewhere | about 10 to 15 min | None; more moving parts |

   **Option C (roadmap):** a scheduled job (for example a Logic App, or a GitHub workflow as the
   deploy identity) runs daily, computes the (caller, resource) pairs of the last 14 days from
   `AzureActivity`, and writes them to a `HuginnKnownPairs` watchlist (or a summary-rule table).
   The fast rule then reads 47 hours of raw rows plus the long-term pairs from that store, so it
   keeps a 14-day memory at 5-minute speed.
5. **CI checks drift instead of applying.** `replay.yml` fails if `terraform plan` shows changes.
   Applies stay manual and reviewed.

## Consequences

- Each nightly run creates and deletes one Logic App and one storage account (no cost).
- The two demo "new pair" rules remember pairs for 47 hours, not 14 days, until option C exists.
- A skipped scheduled run leaves its ingestion interval unevaluated (documented limit).
- The identity-pivot branch of `fenrir-chain` and branch A of `storage-keys-listed` need a real
  managed identity acting off-host, so they are validated only in the purple-team run.
