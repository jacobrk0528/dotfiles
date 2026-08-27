#!/usr/bin/env bash

DIR="/home/jkrebs/Documents/TrinityRoad/local-git/EventTracking"
NAME="event"

cd $DIR
# new-session lands its window on the ambient base-index (1 here), so pin it to
# the index this layout wants instead of assuming base-index 0.
tmux new-session -d -s $NAME -n claude -c $DIR
tmux move-window -d -s $NAME:^ -t $NAME:0 2>/dev/null

tmux send-keys -t $NAME:0 "cd $DIR && clear" C-m
tmux send-keys -t $NAME:0 "claude" C-m

tmux new-window -d -t $NAME:1 -n nvim -c $DIR
tmux send-keys -t $NAME:1 "cd $DIR" C-m
tmux send-keys -t $NAME:1 "clear" C-m
tmux send-keys -t $NAME:1 "nvim ." C-m

tmux new-window -d -t $NAME:2 -n shell -c $DIR
tmux send-keys -t $NAME:2 "cd $DIR && clear" C-m

tmux new-window -d -t $NAME:3 -n dagobah -c $DIR
tmux send-keys -t $NAME:3 "cd $DIR && clear && ssh dagobah" C-m
tmux send-keys -t $NAME:3 "cd /www/services/EventTracking && clear" C-m

tmux select-window -t $NAME:1
tmux attach -t $NAME
