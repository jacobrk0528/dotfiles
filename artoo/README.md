# artoo

Goal-driven computer use on Hyprland. Code enumerates candidates (actions, apps, windows,
on-screen elements), **Jev** (TypeSafe's System One model) picks among them, and an LLM
writes any text (plans, what to type). Full plan: `~/.claude/plans/can-you-help-me-dazzling-wozniak.md`.

Lives in `~/dotfiles/artoo` (formerly the standalone `jev-pilot` project); the CLI is `artoo`.

## Setup
Keys come from the shared `~/dotfiles/.env`: `TYPESAFE_API_KEY`, `OPENAI_API_KEY`, and optionally
`OPENAI_MODEL` / `OPENAI_PLANNER_MODEL` / `JEV_*`. Only those prefixes are loaded (see `src/env.ts`).
```sh
bun install
sudo pacman -S ydotool grim wtype uv      # desktop input, screenshots, local RapidOCR
# dotfiles/scripts/link.sh links hypr/services/ydotool.service into the user units.
systemctl --user daemon-reload
systemctl --user enable --now ydotool     # starts with the graphical session; retries device access
```

## Use
```sh
bun run src/cli.ts --dry-run "open youtube on workspace 3"   # show Jev's decision only
bun run src/cli.ts "focus slack"                            # decide + act
bun run src/cli.ts --step "go to workspace 7"               # confirm every action
bun run src/cli.ts list                                   # actions + params
bun run src/cli.ts act desktop.describe                   # text state Jev will see
bun run src/cli.ts act browser.open_url --url https://youtube.com --workspace 3
bun run src/cli.ts act keyboard.key --combo ctrl+l
bun run src/cli.ts act mouse.click --x 960 --y 540
bun test
```

## Quickshell assistant

`SUPER+A` focuses the dock prompt, which calls `artoo ask --json`. Questions can use
`desktop_task` to find windows on any monitor/workspace, reveal scratchpads, launch an app,
navigate its UI and return an evidence-checked answer. Information lookups restore the
original monitor, window, workspace visibility and cursor afterward.

A Brave window is read as a whole, not one tab: every page it is showing is a pane (two in
split view), each with its own screenshot and controls, and the planner can read one pane
while typing into the other. It also sees the window's background tabs and can `switch_tab`
or `open_url`; web apps are never "launched" as a second browser.

Operations: click, double/right click, hover, drag, type (replace a field), keys (a typed
sequence such as `["9/8/26", "{tab}", "Discover", "{enter}"]` for data entry), single
shortcuts, scroll, tab switching, opening a URL or another app.

The planner sees fresh PNG screenshots plus readable text and controls. Brave uses CDP;
native apps use grim and local RapidOCR. DOM controls have stable node identities and row
context, so repeated Edit buttons stay distinct. Repetitive inspections maintain a logged
checklist of discovered/pending items and observed field values. Returning to a list does
not reset that checklist, and incomplete runs report their partial findings.

### Checkbook workflow

Copying bank or card transactions into the Checkbook sheet has its own path
(`src/workflows/ledger.ts`), because both sides can be read exactly instead of looked at:

```sh
artoo ledger --dry-run "discover card"   # show the rows it would add; types nothing
artoo ledger "chase card"                # asks once, types, verifies
```

From the dock, any request about entering an account's transactions routes here ("do my
savings", "same as !24 for the chase card"). It picks the sheet tab and the bank page from
the request among all open browser tabs, reads the tab as CSV from inside the sheet's own
page, reads the bank page's text, and makes one model call for the rows to add, in that
tab's format and wording, posted transactions only. If the bank's site is open on another
page it clicks through to the account (navigation only, checked by the policy judge). One
approval covers the batch; the rows are typed, then the tab is read again and compared cell
by cell. With no sheet or bank page open it falls back to the planner.

Tab layout it keeps: settled transactions in one block, a one-row gap, then the transactions
that were pending when typed. Everything from the gap down is rewritten each run: what has
posted since joins the settled block (with its posted date and amount, keeping the category
already given to that row), then one blank row, then what is pending now, dated tomorrow.
New rows get no category and checkboxes are never touched. It changes nothing unless the
bank page reaches back to a transaction already in the settled block.

Speed: every planner round is a model call of several seconds, so the loop is built to need
few of them. Browser pages are read whole (text scrolled out of view is included, marked
off-screen), a scroll moves most of a screenful, one plan may line up to four operations
that run back to back, and the planner keeps `notes` that are handed back each round so it
never has to re-read a screen. Data entry is one row to check the layout, then all the rest
in a single operation.

Reading and navigation run automatically. A plain content edit (typing into a sheet, doc or
form field) is approved once per site or app for the task and then continues without asking.
Sending, posting, paying, deleting, settings changes and uncertain
operations always require approval, including keystrokes that submit messages and typing
into autosaved fields. Opening an existing editor to inspect it is navigation. Search
queries are navigation; editing the data in that view is a write. Shell execution only
auto-allows a small positive list of read-only commands. Optional read exceptions live in
`guardrails.yaml`; the default app/site lists are empty.

```sh
artoo doctor                         # installed tools, compositor, uinput, mouse daemon
artoo context                        # origin snapshot (the dock captures this before asking)
artoo ask --json "What did Bryan last say in Slack?"
artoo history                        # saved conversations, timings and estimated cost
artoo history --json <id>            # includes linked run details
bun run typecheck
```

Every conversation has a short id, shown in the history panel and by `artoo history` as
`!12`. Typing it in a later prompt attaches that conversation's record (the request, each
step taken, the outcome), so "do exactly what you did in !12 again with the new tab" works.
`artoo history 12` opens one by its id. Ids are files in `conversations/refs/` and never
change, even when older conversations are deleted.

The dock's **Stop** button sends SIGTERM; model requests and UI work stop, then lookup
restoration runs before exit. A cross-process lock serializes desktop input across prompts
on different monitors. `SUPER+SHIFT+A` opens history, including expandable screenshot
observations, approvals, verification and per-item inspection progress.

Logs live in `~/.local/share/artoo/` (outside the repo: they hold screenshots and answers):
`conversations/<id>.jsonl` links to `runs/<id>/events.jsonl` and its observation PNGs.
`OPENAI_MODEL` handles quick answers and policy checks; `OPENAI_PLANNER_MODEL` must accept
image inputs. `OPENAI_GUARD_MODEL` can override the policy-check model.

## Layout
- `src/exec.ts`: the one place processes get spawned (swapped out in tests)
- `src/harness/`: hyprctl, wtype/ydotool, grim, .desktop index
- `src/perceive/`: desktop → text `state`
- `src/actions.ts`: action registry (zod params, risk tags, Jev pickers), shared by the CLI, Jev, and the LLM
- `src/perceive/candidates.ts`: closed option lists (workspaces, windows, apps, URLs from sites/bookmarks/history)
- `src/jev.ts`: `pickMany` sends several choice questions in one request
- `src/agent.ts`: goal → action (fast path). Low confidence, a risky action, or `--step` asks first
- `runs/<ts>/events.jsonl`: what Jev saw and picked, with the top probabilities
