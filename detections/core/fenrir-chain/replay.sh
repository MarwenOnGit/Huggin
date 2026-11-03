#!/usr/bin/env bash
# Benign replay for fenrir-chain, multi-stage branch: the same caller performs two stages
# (LogicAppCallback, then SecretListing) within the 4-hour window. It reuses the replays of
# logicapp-callback-listed and storage-keys-listed. When the workflow already ran those two in
# the same job, it sets HUGINN_SKIP_SIBLINGS=1 and this script only checks that they ran.
# The identity-pivot branch is validated manually (docs/PURPLE-TEAM.md).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "${HUGINN_SKIP_SIBLINGS:-0}" == "1" ]]; then
  echo "fenrir-chain: stages already produced by the sibling replays in this job"
  exit 0
fi
"$DIR/../logicapp-callback-listed/replay.sh"
"$DIR/../storage-keys-listed/replay.sh"
