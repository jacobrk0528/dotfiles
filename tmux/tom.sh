#!/usr/bin/env bash
# TomBombadil -- Bun/Hono Slack-native ops agent.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

b_init tom "$HOME/Documents/TrinityRoad/local-git/TomBombadil"

b_cd 0
b_send 0 "claude"

b_window 1 nvim
b_cd 1
b_send 1 "nvim ."

b_window 2 shell
b_cd 2

# dagobah is production; the perceptor staging box is driven by `make deploy`.
b_ssh 3 dagobah dagobah /www/services/TomBombadil

b_window 9 dev
b_cd 9
b_send 9 "bun run dev"

b_finish 1
