#!/usr/bin/env bash
# Benign replay for logicapp-callback-listed (Fenrir X-13).
# Creates a FRESH Logic App (Consumption, HTTP Request trigger, never run) with a unique name,
# lists its trigger callback URL once (response discarded), then deletes it.
# A fresh workflow per run avoids the baseline trap: the rule only fires on a (caller, workflow)
# pair it has not seen in 14 days (docs/TESTING.md).
set -euo pipefail
# shellcheck source=../../../scripts/replay/lib.sh
source "$(dirname "$0")/../../../scripts/replay/lib.sh"
huginn_preflight

NAME="logic-huginn-replay-$(huginn_run_id)"
ID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Logic/workflows/$NAME"
trap 'huginn_delete "$ID"' EXIT

BODY="$(cat <<JSON
{
  "location": "$LOCATION",
  "tags": {"huginn-replay": "$(huginn_run_id)"},
  "properties": {
    "state": "Enabled",
    "definition": {
      "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
      "contentVersion": "1.0.0.0",
      "triggers": {"manual": {"type": "Request", "kind": "Http", "inputs": {"schema": {}}}},
      "actions": {},
      "outputs": {}
    }
  }
}
JSON
)"

huginn_log "create $NAME"
az rest --method put --url "$ARM$ID?api-version=2019-05-01" --body "$BODY" > /dev/null

huginn_log "listCallbackUrl on $NAME (X-13)"
az rest --method post --url "$ARM$ID/triggers/manual/listCallbackUrl?api-version=2019-05-01" > /dev/null
huginn_log "done"
