#!/usr/bin/env bash
# Non-interactive wrapper around main.py for scripted use: reads NetSuite
# credentials from narsil's .env (not passed inline on the command line) and
# runs a query straight through, no nvim editor step.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="/home/jkrebs/Documents/TrinityRoad/local-git/narsil/.env"

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

export NS_DSN="${NETSUITE_DSN}"
export NS_USER="${NETSUITE_USERNAME}"
export NS_PASSWORD="${NETSUITE_PASSWORD}"

query="$1"
dest="${2:-output.csv}"

"$SCRIPT_DIR/venv/bin/python3" "$SCRIPT_DIR/main.py" "$query" -d "$dest"
