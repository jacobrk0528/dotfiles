#!/usr/bin/env bash
# Harpoon for tmux sessions: a short, ordered list of pinned sessions with fixed
# jump keys. Bound in tmux.conf:
#   prefix a        add the current session to the list
#   prefix h/j/k/l  jump to slot 1/2/3/4
#   prefix e        edit the list in nvim (reorder with dd/p, <CR> jumps)
# The list is one session name per line; line number = slot.
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-harpoon"
LIST="$STATE_DIR/list"
SLOT_KEYS=(h j k l)

mkdir -p "$STATE_DIR"
touch "$LIST"

msg() { tmux display-message "harpoon: $*"; }

# slot_label <n> -> "1 (h)", or just "5" past the keyed slots
slot_label() {
  local key=${SLOT_KEYS[$(($1 - 1))]:-}
  [ -n "$key" ] && printf '%s (%s)' "$1" "$key" || printf '%s' "$1"
}

# Strip whitespace and blank lines, drop duplicates keeping the first.
normalize() {
  local tmp
  tmp=$(mktemp "$STATE_DIR/list.XXXXXX")
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$LIST" | awk 'NF && !seen[$0]++' > "$tmp"
  mv "$tmp" "$LIST"
}

cmd_add() {
  local session n
  session=$(tmux display-message -p '#S')
  if n=$(grep -nxF -- "$session" "$LIST" | cut -d: -f1) && [ -n "$n" ]; then
    msg "$session already in slot $(slot_label "$n")"
    return
  fi
  printf '%s\n' "$session" >> "$LIST"
  normalize
  msg "added $session to slot $(slot_label "$(wc -l < "$LIST")")"
}

cmd_go() {
  local n=$1 session
  session=$(sed -n "${n}p" "$LIST")
  if [ -z "$session" ]; then
    msg "slot $(slot_label "$n") is empty"
    return
  fi
  # goto.sh rebuilds a missing session from its builder (or as a plain session).
  "$HERE/goto.sh" "$session"
}

# Runs inside the popup: open the list in nvim, then jump if <CR> picked a line.
cmd_edit() {
  local pick session
  pick=$(mktemp "$STATE_DIR/pick.XXXXXX")
  HARPOON_PICK="$pick" nvim -n -S "$HERE/harpoon.vim" "$LIST" || true
  normalize
  session=$(head -n1 "$pick")
  rm -f "$pick"
  [ -n "$session" ] && "$HERE/goto.sh" "$session"
  return 0
}

case "${1:-}" in
  add)  cmd_add ;;
  go)   [ -n "${2:-}" ] || { echo "Usage: harpoon.sh go <slot>" >&2; exit 1; }; cmd_go "$2" ;;
  edit) cmd_edit ;;
  *)    echo "Usage: harpoon.sh add | go <slot> | edit" >&2; exit 1 ;;
esac
