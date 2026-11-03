#!/usr/bin/env bash
# Benign replay for storage-keys-listed (Fenrir P-12), branch C.
# Creates a FRESH, empty storage account (shared keys and public network access disabled) with a
# unique name, calls listKeys once (response discarded), then deletes it.
# A fresh account per run avoids the baseline trap: branch C only fires on a (caller, account)
# pair it has not seen in 14 days (docs/TESTING.md).
set -euo pipefail
# shellcheck source=../../../scripts/replay/lib.sh
source "$(dirname "$0")/../../../scripts/replay/lib.sh"
huginn_preflight

NAME="sthgr$(huginn_run_id)"   # 5 + 12 = 17 characters, lower-case letters and digits
ID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$NAME"
trap 'huginn_delete "$ID"' EXIT

huginn_log "create $NAME"
az storage account create -n "$NAME" -g "$RG" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false \
  --public-network-access Disabled --https-only true \
  --tags "huginn-replay=$(huginn_run_id)" -o none

huginn_log "listKeys on $NAME (P-12)"
az rest --method post --url "$ARM$ID/listKeys?api-version=2023-01-01" > /dev/null
huginn_log "done"
