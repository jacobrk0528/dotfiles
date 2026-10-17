# agents

A tmux hub for every Claude Code session you have running. A sidebar lists
them all with their state. Pick one and it opens in the pane beside the
sidebar. It is the **same** Claude that lives in its project session, not a
copy: type in the hub, switch to the project session, and carry on there.

```
┌─ agents session ─────────────────────────────────────┐
│ sidebar (bun)  │ nested client → agents-view session │
│ ! narsil    5m │   agents-view holds one window,     │
│ ⠦ dotfiles  2s │   linked from the project session   │
│ ● tom      12m │                                     │
└────────────────┴─────────────────────────────────────┘
```

## Open it

- `prefix g` (row in `tmux/sessions.list`, builder `tmux/agents.sh`)
- `agents` from a shell, which attaches outside tmux or switches inside it

## Starting and closing agents

The project builders (`tmux/<project>.sh`) no longer start Claude, so after a
boot the hub is empty. Each project keeps window 0 (`claude`) as an idle shell
in the project directory. `Alt+n` / `Alt+t` start Claude in that slot when it
is idle and in the same directory, otherwise in a new window. Closing the
Claude in window 0 (`Alt+c`) turns it back into a shell instead of removing
the window.

## States

| Glyph | State | Set by (Claude Code hook) |
|---|---|---|
| `◇` | new, never prompted | `SessionStart`, or no hook state and still titled "Claude Code" |
| `⠦` | running | `UserPromptSubmit`, `PostToolUse` |
| `!` (red) | needs you (permission or question) | `Notification` (`permission_prompt`, `elicitation_dialog`) |
| `●` (green) | finished, unread | `Stop`, when nobody was looking at it |
| `○` | finished, seen | `Stop` + you viewed it |
| `·` | unknown (started before the hooks existed) | |

The hooks live in `~/.claude/settings.json` and call
`~/.tmux/agent_state.sh <Event>`. That script stores `@agent_state`,
`@agent_at` and `@agent_seen` as tmux **pane** options. State is kept per
pane because one window can hold several Claudes. The script finds the pane
through Claude's own registry (`~/.claude/sessions/<pid>.json`, whose `tmux`
field names the pane), matching the hook's `session_id`. `$TMUX_PANE` is not
enough: a session sent to the background (`/background`) runs its hooks in
the daemon, where that variable isn't set. A Claude only gets a state
at its next hook event, so an interrupted turn (Esc) stays "running" until
your next prompt.

## Keys (sidebar)

| Key | Action |
|---|---|
| `j`/`k`, arrows | move; the viewer previews the agent under the cursor |
| `Enter`, `l`, click | show it and focus the viewer, ready to type |
| `n` | jump to the next agent that needs you (blocked first, then unread) |
| `1`–`9` | show the Nth agent |
| `o` | leave the hub: switch to the agent in its own project session |
| `t` | start a new Claude in a new window of this agent's session, same directory |
| `x` | close this agent (kills its pane; a session's last window gets a fresh shell instead) |
| `g`/`G` | first/last |
| `J`/`K` | move this agent's session down/up the list (its agents move together) |

The order is saved in `~/.local/state/agents/order` (one session per line), so
it survives a reboot. Sessions not in it go after the others, alphabetically.
When a session holds several agents, a rail (`╭ │ ╰`) at the left edge joins
them and the `:N` window suffix that tells them apart is highlighted.

### From anywhere in the hub (tmux.conf)

These work while you are typing to Claude in the viewer, so you never have to
go back to the sidebar. Outside the hub they keep their usual meaning.

| Key | Action |
|---|---|
| `Alt+j` / `Alt+k` | next / previous agent; focus stays in the viewer |
| `Alt+1`–`Alt+9` | show agent N |
| `Alt+u` | next agent that needs you |
| `Alt+t` | new Claude in the current agent's project (sidebar `t`) |
| `Alt+n` | popup: pick a session, start a new Claude there (`agents --pick`) |
| `Alt+c` | close the current agent (sidebar `x`) |
| `Alt+h` / `Alt+l` | focus sidebar / viewer |

They work by sending the sidebar's own keys to pane `agents:0.0`, and all of
them except `Alt+l` and `Alt+1`–`Alt+9` leave focus on the sidebar, so the
arrows work next. Those two land in the viewer, ready to type.

## How the viewer works

`agents-view` holds a placeholder window plus the one agent window being
shown. Showing an agent runs `link-window` to add its window to
`agents-view`, then `unlink-window` (never with `-k`) to drop the previous
one. The window is therefore shared, never copied or killed. `agents-view`
has `prefix None` and `status off`, so `C-a` still drives the outer hub and
`C-a C-a` reaches Claude.

## Known limits

- Inside the hub, `Alt+j/k/n/u/t/c/h/l` and `Alt+1-9` belong to the hub, so Claude
  never sees them there.
- A shared window resizes to whichever client used it last
  (`window-size latest`). Switching between the hub and the project session
  reflows Claude.
- Claude Code only. Codex and opencode would need their own notify hooks
  writing the same pane options.
- The hooks are in `~/.claude/settings.json`, which is not in dotfiles, so the
  laptop needs the same `hooks` entries.

## Develop

```sh
bun test           # parsing and label tests
bunx tsc --noEmit
```

Test against a throwaway tmux server that you name with an explicit `-S`
socket on every command. Run the scripts under test from inside that server's
panes. Never rely on `TMUX_TMPDIR`: `$TMUX` takes precedence over it.
