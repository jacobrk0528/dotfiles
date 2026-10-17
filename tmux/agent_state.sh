#!/usr/bin/env bash
# Claude Code hook: records what the agent in this pane is doing as tmux pane
# options, which the agents sidebar (scripts/agents) reads with list-panes.
#
#   @agent_state  new | running | attention | done
#   @agent_at     epoch seconds of the last change
#   @agent_seen   0 when a finished/blocked agent has not been looked at yet
#
# Usage (from ~/.claude/settings.json): agent_state.sh <HookEventName>
# Per pane rather than per window: one window can hold several Claudes.
# Must stay fast and silent -- PostToolUse runs it after every tool call.

input=$(head -c 4096; cat >/dev/null)         # session_id is near the start

# Find the pane from Claude's own registry (~/.claude/sessions/<pid>.json
# records "tmux":"session:@win.%pane"), not $TMUX_PANE: a session sent to the
# background (/background) runs its turns and hooks in the daemon, which has no
# $TMUX_PANE. The pane's process lists the job as "parkedJobId" (the first 8
# characters of the session id).
pane_for_session() {
  local sid file tmuxf
  sid=$(printf '%s' "$input" | grep -o '"session_id" *: *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  [ -n "$sid" ] || return 1
  file=$(grep -l -e "\"sessionId\":\"$sid\"" -e "\"parkedJobId\":\"${sid:0:8}\"" \
    "$HOME"/.claude/sessions/*.json 2>/dev/null | head -1)
  [ -n "$file" ] || return 1
  tmuxf=$(grep -o '"tmux":"[^"]*"' "$file" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  [ -n "$tmuxf" ] || return 1
  printf '%s\n' "${tmuxf##*.}"
}

PANE=$(pane_for_session) || PANE=${TMUX_PANE:-}
[ -n "$PANE" ] || exit 0                      # not running inside tmux
tmux display -p -t "$PANE" '' >/dev/null 2>&1 || exit 0   # pane is gone
TMUX_PANE=$PANE

set_state() {
  tmux set -p -t "$TMUX_PANE" @agent_state "$1" \; \
       set -p -t "$TMUX_PANE" @agent_at "$(date +%s)" \; \
       set -p -t "$TMUX_PANE" @agent_seen "$2" 2>/dev/null
}

# Something you are already looking at needs no "unread" marker. The hub's
# viewer client keeps showing its last pick, so it only counts while someone is
# actually in the hub (same rule as watchedWindows() in scripts/agents).
watched() {
  local win hub s w
  win=$(tmux display -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)
  hub=$(tmux display -p -t '=agents:' '#{session_attached}' 2>/dev/null)
  while read -r s w; do
    [ "$w" = "$win" ] || continue
    [ "$s" = agents-view ] && [ "${hub:-0}" -eq 0 ] && continue
    echo 1; return
  done < <(tmux list-clients -F '#{session_name} #{window_id}' 2>/dev/null)
  echo 0
}

case ${1:-} in
  SessionStart)                 set_state new 1 ;;
  UserPromptSubmit|PostToolUse) set_state running 1 ;;
  Notification)                 set_state attention "$(watched)" ;;  # matcher limits this to prompts
  Stop)                         set_state done "$(watched)" ;;
  SessionEnd)
    tmux set -pu -t "$TMUX_PANE" @agent_state \; \
         set -pu -t "$TMUX_PANE" @agent_at \; \
         set -pu -t "$TMUX_PANE" @agent_seen 2>/dev/null ;;
esac
exit 0
