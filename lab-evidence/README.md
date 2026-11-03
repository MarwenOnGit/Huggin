# Lab evidence

Raw `AzureActivity` rows captured in Phase 3, one file per Fenrir operation: `<op-id>.json`
(for example `X-13.json`). They are the proof behind every "verify in lab" answer in
[../docs/STATUS.md](../docs/STATUS.md).

Rules for these files:
- Each one comes from a benign replay on a Huginn lab resource, run with explicit approval.
- Secrets are redacted before saving: no keys, passwords, SAS signatures, callback URLs, tokens or
  `Authorization` headers. Replays discard command output (`> /dev/null`), so none should be present.
- Unredacted query output goes to `lab-evidence/raw/`, which is git-ignored, and is deleted after redaction.
- Each file records the capture date, the query used and the replay that produced it.
