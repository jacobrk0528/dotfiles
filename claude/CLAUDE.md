# Two machines, one set of files

`~/Documents` and `~/Downloads` are kept identical between the desktop
(`optimus`, Arch Linux) and the laptop (macOS) by Syncthing. Projects live
under `~/Documents`, including their `.git` directories and uncommitted work.

## Check sync status before editing

Before the first edit in a session to anything under `~/Documents` or
`~/Downloads`, and again after any long pause, you MUST run:

    sync-status

- Exit 0, "Safe to edit": go ahead.
- Exit 1, "DO NOT EDIT": the other machine's changes are still arriving. Do not
  edit, write, delete, or run anything that modifies files there (including
  `git` commands that touch the working tree or index, formatters, and
  installs). Run `sync-status --wait`, then re-read any file you had already
  read, since it may have changed.
- Exit 2, "CANNOT CONFIRM": the other machine is not connected, so it may hold
  newer work. Ask the user before editing.

This applies to edits made through Bash (`sed`, redirects, scripts, `git
checkout`) as much as to the Edit and Write tools. A hook blocks Edit and Write
while changes are arriving, but nothing guards Bash except you.

Editing during a sync leaves `*.sync-conflict-*` copies or, inside `.git`, a
corrupted repository. If you see a `sync-conflict` file, tell the user rather
than deleting it.

## What is not synced

`node_modules`, `venv`/`.venv`, Android `build` output, `.gradle`, and
`local.properties` are per machine (list: `~/Documents/.stglobalignore`).
Missing dependencies on one machine are expected: install them, do not copy
them across.

Home is `/home/jkrebs` on the desktop and `/Users/jkrebs` on the laptop, so
never write an absolute home path into a synced file. Git worktrees record
absolute paths by default, which breaks them on the other machine: always
create them with `git worktree add --relative-paths`, and fix an existing one
with `git worktree repair --relative-paths <path>` from the main checkout.

Each Android project needs its own `android/local.properties` per machine
(`sdk.dir` differs); copy the other keys from the other machine's file.

`.DS_Store` files are never synced. Where a repo has one committed, it shows
as deleted on the laptop; leave that out of commits.

## Databases

Postgres (5432), MariaDB (3306) and Valkey (6379) run only on the desktop. On
the laptop, `localhost` on those ports is forwarded there by `optimus-link`, so
both machines see the same data. Connect over TCP (`-h localhost` /
`-h 127.0.0.1`), not a local socket. If a connection is refused on the laptop,
check `optimus-link status` before assuming the database is down.
