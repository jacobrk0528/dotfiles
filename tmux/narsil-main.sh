#!/usr/bin/env bash
# narsil-main -- the `main` (production) worktree of the narsil repo.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

b_init narsil-main "$HOME/Documents/TrinityRoad/local-git/narsil-main"
b_venv

b_cd 0
b_send 0 "claude"

b_window 1 nvim
b_cd 1
b_send 1 "nvim ."

b_window 2 shell
b_cd 2

b_ssh 3 dagobah dagobah /www/services/narsil

b_finish 1
