#!/usr/bin/env bash
# Non-interactive wrapper around main.py for scripted use: reads NetSuite
# credentials from ~/dotfiles/.env (not passed inline on the command line) and
# runs a query straight through, no nvim editor step.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# NETSUITE_DSN / NETSUITE_USERNAME / NETSUITE_PASSWORD. dotenv.sh takes values
# literally, so a password with shell metacharacters survives intact.
. "$HOME/dotfiles/scripts/dotenv.sh"
: "${NETSUITE_DSN:?not set in $DOTFILES_ENV}" "${NETSUITE_USERNAME:?not set in $DOTFILES_ENV}" "${NETSUITE_PASSWORD:?not set in $DOTFILES_ENV}"

export NS_DSN="${NETSUITE_DSN}"
export NS_USER="${NETSUITE_USERNAME}"
export NS_PASSWORD="${NETSUITE_PASSWORD}"

query="$1"
dest="${2:-output.csv}"

"$SCRIPT_DIR/venv/bin/python3" "$SCRIPT_DIR/main.py" "$query" -d "$dest"
