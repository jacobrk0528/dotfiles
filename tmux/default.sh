#!/usr/bin/env bash
# Builder for any session NOT in sessions.list, e.g. `ta temp`. Same layout
# everywhere, rooted in the directory you ran it from:
#   0 claude   1 nvim   2 shell
#
#   default.sh <session> [dir]     dir defaults to $PWD
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

[ -n "${1:-}" ] || { echo "Usage: default.sh <session> [dir]" >&2; exit 1; }

b_init "$1" "${2:-$PWD}"
b_venv

b_cd 0
b_send 0 "claude"

b_window 1 nvim
b_cd 1
b_send 1 "nvim ."

b_window 2 shell
b_cd 2

b_finish 0
