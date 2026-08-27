#!/usr/bin/env bash
# Shared parser for ~/.tmux/sessions.list. Source this; do not execute it.

TMUX_DIR="${TMUX_DIR:-$HOME/.tmux}"
SESSIONS_LIST="$TMUX_DIR/sessions.list"

# Emits "key<TAB>session<TAB>builder<TAB>autostart" for every non-comment row.
sessions_each() {
  [ -r "$SESSIONS_LIST" ] || { echo "sessions.list not found: $SESSIONS_LIST" >&2; return 1; }
  while read -r key session builder autostart _rest; do
    case "$key" in ''|'#'*) continue ;; esac
    [ -n "${session:-}" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$key" "$session" "${builder:--}" "${autostart:-no}"
  done < "$SESSIONS_LIST"
}

# builder_for <session> -> prints script path, or nothing if the row says '-'
builder_for() {
  local want=$1 key session builder auto
  while IFS=$'\t' read -r key session builder auto; do
    [ "$session" = "$want" ] || continue
    [ "$builder" = "-" ] && return 0
    printf '%s\n' "$TMUX_DIR/$builder.sh"
    return 0
  done < <(sessions_each)
}

# resolve_name <input> - map a case-insensitive session OR builder name to the
# canonical session name. Falls back to the input unchanged for ad-hoc sessions.
resolve_name() {
  local want key session builder auto
  want=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  while IFS=$'\t' read -r key session builder auto; do
    if [ "$(printf '%s' "$session" | tr '[:upper:]' '[:lower:]')" = "$want" ] \
       || [ "$(printf '%s' "$builder" | tr '[:upper:]' '[:lower:]')" = "$want" ]; then
      printf '%s\n' "$session"
      return 0
    fi
  done < <(sessions_each)
  printf '%s\n' "$1"
}

# session_exists <name>  (exact match; session names are case sensitive)
session_exists() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -qxF "$1"
}

# ensure_session <name> - create it detached if missing. Never attaches.
#
# The per-session builders end in `tmux attach -t $NAME` so that running them by
# hand from a terminal drops you into the session. Headless that call fails with
# "open terminal failed" and a non-zero exit AFTER the session is fully built, so
# we feed them /dev/null, ignore their status, and judge success by whether the
# session actually exists.
ensure_session() {
  local name=$1 builder
  session_exists "$name" && return 0
  builder=$(builder_for "$name")
  if [ -n "$builder" ] && [ -x "$builder" ]; then
    "$builder" </dev/null 2>/dev/null || true
  else
    tmux new-session -d -s "$name" -n "$name" </dev/null
  fi
  session_exists "$name"
}
