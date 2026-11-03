#!/usr/bin/env bash
# Safety net after replays: delete every resource in the lab resource group that carries the
# huginn-replay tag (replays tag what they create). Each replay already deletes its own
# resources through a trap; this catches cancelled or killed jobs.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
huginn_preflight

mapfile -t IDS < <(az resource list -g "$RG" --query "[?tags.\"huginn-replay\" != null].id" -o tsv)
if [[ ${#IDS[@]} -eq 0 || -z "${IDS[0]}" ]]; then
  huginn_log "nothing to clean up"
  exit 0
fi
for id in "${IDS[@]}"; do
  huginn_delete "$id"
done
