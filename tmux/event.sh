#!/usr/bin/env bash
# EventTracking -- Go event/attribution server (server/) feeding BigQuery.
# The pixel now lives in narsil-connector, not this repo.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

b_init event "$HOME/Documents/TrinityRoad/local-git/EventTracking"

b_cd 0
b_send 0 "claude"

b_window 1 nvim
b_cd 1
b_send 1 "nvim ."

b_window 2 shell
b_cd 2

# Lowercase 'e' -- the box has /www/services/eventTracking, which is what
# server/makefile scps to. The old capitalised path never existed there.
b_ssh 3 dagobah dagobah /www/services/eventTracking

b_finish 1
