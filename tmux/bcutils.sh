#!/usr/bin/env bash
# bc_utils -- flat Python BI scripts (forecasting, order alerts, Slack reports).
# No claude window: this layout starts at 1 with the editor.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

b_init bcUtils "$HOME/Documents/TrinityRoad/local-git/bc_utils" nvim 1
b_venv

b_cd 1
b_send 1 "nvim ."

b_window 2 shell
b_cd 2

b_ssh 3 bespin bespin /www/bc_utils

b_finish 1
