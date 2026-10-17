# Two machines, one set of files

`~/Documents` and `~/Downloads` are kept identical between the desktop
(`optimus`, Arch Linux) and the laptop (macOS) by Syncthing. Projects live
under `~/Documents`, including their `.git` directories and uncommitted work.

Each machine syncs only with an always-on hub, `bumblebee` (192.168.1.110 in
the homelab; reached through the tailnet's subnet route when away), never with
the other machine. The user works on one machine at a time, so the other one
being switched off is normal and is not a reason to hold off.

## Check sync status before editing

Before the first edit in a session to anything under `~/Documents` or
`~/Downloads`, and again after any long pause, you MUST run:

    sync-status

- Exit 0, "Safe to edit": go ahead.
- Exit 1, "DO NOT EDIT": changes from the hub are still arriving. Do not
  edit, write, delete, or run anything that modifies files there (including
  `git` commands that touch the working tree or index, formatters, and
  installs). Run `sync-status --wait`, then re-read any file you had already
  read, since it may have changed.
- Exit 2, "CANNOT CONFIRM": the hub is not connected (or Syncthing is not
  running), so it may hold newer work. Ask the user before editing.
- "still sending N items to bumblebee" is still exit 0: fine to keep editing
  here, but tell the user if they are about to switch machines.

This applies to edits made through Bash (`sed`, redirects, scripts, `git
checkout`) as much as to the Edit and Write tools. A hook blocks Edit and Write
while changes are arriving, but nothing guards Bash except you.

Editing during a sync leaves `*.sync-conflict-*` copies or, inside `.git`, a
corrupted repository. Syncthing keeps the newer edit under the real name and
the older one as the conflict copy, and `sync-notify` pops up a notification
when that happens. If you see a `sync-conflict` file, tell the user rather than
deleting it. Replaced and deleted files are kept in `.stversions` (14 days on
each machine, 30 on the hub).

Setup: `sync-setup hub ...` on bumblebee, `sync-setup client bumblebee <id>
tcp://192.168.1.110:22000` on each machine.

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
