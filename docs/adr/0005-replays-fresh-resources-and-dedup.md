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
3. **Ingestion-time deduplication.** Rules treat rows as new when `ingestion_time()` falls in the
   last rule interval, and build baselines from earlier rows. Rule-level suppression was rejected:
   it hides every alert of the rule for the suppression period, including the second replay of the
   baseline-trap test. Alert grouping was rejected: it groups alerts into incidents but does not
   stop duplicate alerts.
4. **CI checks drift instead of applying.** `replay.yml` fails if `terraform plan` shows changes.
   Applies stay manual and reviewed.

## Consequences

- Each nightly run creates and deletes one Logic App and one storage account (no cost).
- A skipped scheduled run leaves its ingestion interval unevaluated (documented limit).
- The identity-pivot branch of `fenrir-chain` and branch A of `storage-keys-listed` need a real
  managed identity acting off-host, so they are validated only in the purple-team run.
