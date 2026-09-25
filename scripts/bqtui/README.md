# bqtui

A BigQuery workbench for the terminal, modeled on the web console: an
explorer on the left, a SQL editor top-right, and a results grid
bottom-right. Built with [OpenTUI](https://github.com/anomalyco/opentui)
(`@opentui/react`) and Bun.

Everything talks to BigQuery through the `bq` CLI, so it reuses your
existing `gcloud` auth and behaves exactly like `bq` does. No API keys,
no service accounts.

```
┌─ Explorer ──────────┐ 1 ≡ brand-counts •  2 ▤ Ads.ads_CampaignStats  3 ≡ Query 3
│ ▾ ⊞ narsil (active) │┌─ brand-counts • (saved) ─────────────────────────────────┐
│   ▾ Ads             ││ 1 SELECT                                                 │
│      ◇ ads_Campaign…││ 2     brand,                                             │
│      ▦ p_ads_Campai…││ 3     COUNT(*) AS n                                      │
│   ▸ anduril         ││ 4 FROM `anduril-3018.Attentive.attentive`                │
│   ▸ attentive       ││ 5 GROUP BY 1                                             │
│   ▸ Billing         │└──────────────────────────────── ✓ 4.92 KiB · <$0.01 ─────┘
│                     │┌─ Results ────────────────────────────────────────────────┐
│                     ││ 5 rows · 250 ms · 4.92 KiB processed (<$0.01) · 56 ms slot│
│                     ││   brand            │ n▲                                  │
│                     ││   string           │ integer                             │
│                     ││ 1 Rosary           │      12                             │
└─────────────────────┘└──────────────────────────────────────────────────────────┘
 Query finished: 5 rows                          ⊞ narsil · 3 tabs · results
 j/k h/l move · Enter row · s sort · y/Y copy · e/E export · z zoom · F1 help
```

## Features

**Explorer** – projects → datasets → tables with vim navigation, a `/`
filter that searches every table in the project, table-type icons
(table / view / materialized view / external / snapshot), refresh, and
one-key actions: open schema, preview, insert a fully-qualified reference
into the editor, copy the reference.

**Projects** – switch the active project (where queries run and bill) from
a picker, and pin any other projects you can access so they show in the
explorer alongside it. Persisted between runs.

**Editor** – SQL syntax highlighting, line numbers, undo/redo, run the
whole buffer or just the selection, `sqlfluff` formatting (honours your
`~/.sqlfluff`), dry-run validation with bytes-processed and cost estimate
(also refreshed automatically as you type), cancel a running query.

**Tabs** – as many query tabs and schema tabs as you like. Each query tab
keeps its own results and stats. Tabs, editor contents, and layout are
restored on the next launch.

**Schema tabs** – fields with types/modes/descriptions (nested RECORDs
expanded), row count, size, partitioning and clustering, created/modified
times, labels, and the SQL definition for views.

**Results** – column order preserved, types shown under each header,
numeric right-alignment, row/column cursor with horizontal scrolling, sort
by any column, row detail view with pretty-printed structs, copy
cell/row/all as TSV or JSON, export CSV/JSON, elapsed time, bytes processed,
cache hits, slot time, and DDL/DML confirmations.

**History and saved queries** – every run is logged with its outcome and
stats (`Ctrl+P` to browse and reopen); save named queries to
`~/.config/bqtui/queries/` and reopen them in a tab.

**Dataform** (explorer section 2) – repositories per project across the
configured regions, workspaces with their file tree (open `.sqlx`/`.js`
files), compilations with every compiled action's SQL (views, tables,
incrementals, assertions, operations) and compile errors, workflow
invocations with per-action state, duration and failure reasons, release
and workflow schedules. Compile a workspace, start an invocation, cancel a
running one, or open any compiled SQL in a query tab. BigQuery Studio saved
queries (which are Dataform repositories under the hood) show up here too
and open as editable query tabs.

**Cloud Storage** (explorer section 3) – buckets per project, lazy folder
browsing, object preview (text/JSON, with size/type/updated/MD5), download,
copy or insert the `gs://` URI, and one-key `CREATE EXTERNAL TABLE` /
`LOAD DATA` statements for a file or a whole prefix.

Mouse works too: click a pane, a tab, or an explorer row; wheel to scroll.

## Install

Requirements: [Bun](https://bun.sh), the `bq` CLI (Google Cloud SDK,
authenticated), and optionally `sqlfluff` for formatting and `wl-copy`
(or `xclip`/`xsel`/`pbcopy`) for the clipboard.

The launcher installs dependencies on first run:

```sh
~/dotfiles/scripts/bqtui/bqtui        # or just `bqtui` after `scripts/link.sh`
```

`scripts/link.sh` symlinks the launcher to `~/.local/bin/bqtui`.

Developer commands (from `scripts/bqtui/`): `bun start`, `bun run dev`
(watch mode), `bun test`, `bun run typecheck`.

## Keys

Press `F1` (or `?` outside the editor) at any time for the full reference.

| Global | |
| --- | --- |
| `F2` / `F3` / `F4` | Focus explorer / editor / results |
| `Ctrl+H` / `J` / `K` / `L` | Move focus left / down / up / right between panes (tmux-style) |
| `Tab` / `1` `2` `3` (explorer) | Switch explorer section: BigQuery · Dataform · Storage |
| `F6` | Toggle the explorer sidebar |
| `Ctrl+B` | Toggle the results panel |
| `Ctrl+T` / `Ctrl+X` | New query tab / close tab (`Ctrl+W` also closes outside the editor) |
| `Ctrl+PgUp` / `Ctrl+PgDn` | Previous / next tab |
| `Alt+1…9` | Jump to tab |
| `Alt+P` | Switch active project / pin projects |
| `Ctrl+O` / `Ctrl+S` | Open saved query / save |
| `Ctrl+P` | Query history |
| `Ctrl+Y` | Copy all results (TSV) |
| `Ctrl+Q` | Quit |

| Editor | |
| --- | --- |
| `Ctrl+Enter` / `F5` / `Alt+Enter` | Run query (selection only, if any) |
| `Ctrl+G` | Dry run: validate, bytes, cost |
| `Ctrl+L` | Format with sqlfluff |
| `Esc` | Cancel the running query |
| `Ctrl+Z` / `Ctrl+R` | Undo / redo |
| `Ctrl+A` | Select all |

| Explorer | |
| --- | --- |
| `j` `k` `h` `l` (or arrows) | Move, collapse / expand (`h` on a leaf jumps to its parent) |
| `g` / `G`, `Ctrl+D` / `Ctrl+U`, PgUp / PgDn | Jump / page |
| `Enter` | Open table schema, or toggle a project/dataset |
| `p` / `i` / `y` | Preview table · insert reference into editor · copy reference |
| `/` | Filter (loads every dataset's tables so the filter can see them; `Esc` clears) |
| `r` | Refresh node |
| `P` | Projects picker |

| Dataform explorer | |
| --- | --- |
| `Enter` | Open file / compiled SQL / saved query / invocation action |
| `e` | Open compiled SQL in a new query tab |
| `c` | Compile the selected workspace |
| `x` | Run a compilation · cancel a running invocation (with confirmation) |
| `i` / `y` | Insert / copy the action's table reference (`y` on a repo copies its console URL) |
| `r` | Refresh node |

| Storage explorer | |
| --- | --- |
| `Enter` | Preview object in a tab |
| `d` | Download to the export dir |
| `y` / `i` | Copy / insert `gs://` URI |
| `x` / `L` | Insert `CREATE EXTERNAL TABLE` / `LOAD DATA` for the file or prefix |

| Text tabs (files, compiled SQL, previews) | |
| --- | --- |
| `j` `k` `h` `l` | Scroll |
| `e` | Edit a copy in a new query tab |
| `y` / `d` / `r` | Copy content / download (Storage) / reload |

| Results | |
| --- | --- |
| `j` `k` `h` `l` | Move rows / columns |
| `g` / `G`, `0` / `$` | First / last row, first / last column |
| `Enter` | Row detail |
| `s` | Sort by the current column (asc → desc → off) |
| `y` / `Y` / `c` | Copy row / all rows (TSV) / cell |
| `e` / `E` | Export CSV / JSON to `~/Downloads` |
| `z` | Zoom the results panel |

`Ctrl+Enter` needs a terminal that speaks the kitty keyboard protocol
(Ghostty, kitty, WezTerm, foot); inside tmux use `F5` or `Alt+Enter`.

## Files

| Path | Purpose |
| --- | --- |
| `~/.config/bqtui/config.json` | Active project, pinned projects, `maxRows` (default 1000), `exportDir`, `sidebarWidth`, `dataformRegions`, `previewBytes` |
| `~/.config/bqtui/session.json` | Open tabs and layout, restored on launch |
| `~/.config/bqtui/history.jsonl` | One line per executed query |
| `~/.config/bqtui/queries/*.sql` | Saved queries |

## How it works

- Listing and metadata come from `bq ls --format=json` and
  `bq show --format=json`.
- Queries run as `bq query --format=json --job_id=bqtui_…` in the active
  project. Because `bq`'s JSON output sorts keys alphabetically, a dry run
  is issued concurrently to recover the real column order and types (it
  also gives the bytes estimate). Job statistics are fetched afterwards
  with `bq show -j`, and `Esc` cancels via `bq cancel`.
- Cost estimates use on-demand pricing ($6.25 / TiB) and are indicative
  only.
- Syntax highlighting is a small hand-written tokenizer feeding OpenTUI's
  highlight ranges; OpenTUI ships no SQL tree-sitter grammar.
- Dataform uses the REST API (`dataform.googleapis.com/v1beta1`) with a
  token from `gcloud auth print-access-token`, since there is no `gcloud
  dataform` command group. Repositories are scanned in `dataformRegions`.
- Cloud Storage uses `gcloud storage ls --json`, `objects describe`,
  `cat -r`, and `cp`.

## Ideas for later

See [TODOS.md](TODOS.md).
