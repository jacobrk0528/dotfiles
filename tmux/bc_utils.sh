#!/usr/bin/env bash
# bc_utils -- flat Python BI scripts (forecasting, order alerts, Slack reports).
# uv-managed .venv, which b_venv finds on its own.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

b_init bc_utils "$HOME/Documents/TrinityRoad/local-git/bc_utils"
b_venv

b_cd 0
b_send 0 "claude"

b_window 1 nvim
b_cd 1
b_send 1 "nvim ."

b_window 2 shell
b_cd 2

b_ssh 3 bespin bespin /www/bc_utils

b_finish 1
