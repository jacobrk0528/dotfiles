#!/usr/bin/env bash
# narsil -- BigQuery ETL, `staging` worktree. Uses a uv-managed .venv, which
# b_venv finds on its own; do not hardcode the venv path here again.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

b_init narsil "$HOME/Documents/TrinityRoad/local-git/narsil"
b_venv

b_cd 0
b_send 0 "claude"

b_window 1 nvim
b_cd 1
b_send 1 "nvim ."

b_window 2 shell
b_cd 2

b_ssh 3 dagobah dagobah /www/staging/narsil

b_finish 1
