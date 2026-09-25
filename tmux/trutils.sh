#!/usr/bin/env bash
# trUtils -- Laravel + Vue/Inertia internal admin platform.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

b_init trUtils "$HOME/Documents/TrinityRoad/local-git/trUtils"

b_cd 0
b_send 0 "claude"

b_window 1 nvim
b_cd 1
b_send 1 "nvim ."

b_window 2 shell
b_cd 2

b_ssh 3 alderaan alderaan /www/services/trUtils

b_window 4 logs
b_send 4 "cd $DIR && php artisan log:clear && clear && tail -f storage/logs/laravel.log"

b_window 9 dev
b_send 9 "cd $DIR && clear && composer run dev"

b_finish 1
