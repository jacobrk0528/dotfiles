#!/usr/bin/env bash
# Interactive wrapper around main.py: opens nvim on a persistent query file
# (so your last query is still there to edit/rerun), collapses it to one
# line, and runs it through the dedicated venv regardless of whatever venv
# (if any) is active in the current shell.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PYTHON="$SCRIPT_DIR/venv/bin/python3"
MAIN_PY="$SCRIPT_DIR/main.py"

dest="output.csv"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--destination)
      dest="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

tmpfile="$SCRIPT_DIR/.last_query.sql"

nvim "$tmpfile"

# Strip -- line comments, join lines, squeeze whitespace into a single line.
query="$(sed 's/--.*$//' "$tmpfile" | tr '\n' ' ' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')"

if [[ -z "$query" ]]; then
  echo "Empty query, aborting." >&2
  exit 1
fi

"$VENV_PYTHON" "$MAIN_PY" "$query" -d "$dest"
