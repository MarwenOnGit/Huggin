#!/usr/bin/env bash
# Benign replay for this rule. Not implemented yet (Phase 4/5).
# It must act only on Huginn lab resources, discard all outputs (> /dev/null),
# never print or store secrets, and clean up with a trap.
set -euo pipefail
echo "replay not implemented yet for $(basename "$(dirname "$0")")" >&2
exit 2
