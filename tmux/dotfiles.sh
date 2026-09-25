#!/usr/bin/env bash
# Builder for the "dotfiles" session.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

b_init dotfiles "$HOME/dotfiles"

b_cd 0
b_send 0 "claude"

b_window 1 nvim
b_cd 1
b_send 1 "nvim ."

b_finish 0
