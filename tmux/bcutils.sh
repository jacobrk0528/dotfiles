#!/usr/bin/env bash

DIR="/home/jkrebs/Documents/TrinityRoad/local-git/bc_utils"
NAME="bcUtils"

cd $DIR
# new-session lands its window on the ambient base-index, so pin it to index 1
# (the editor window) rather than assuming base-index 0 and colliding with it.
tmux new-session -d -s $NAME -n nvim -c $DIR
tmux move-window -d -s $NAME:^ -t $NAME:1 2>/dev/null

tmux send-keys -t $NAME:1 "cd $DIR" C-m
tmux send-keys -t $NAME:1 "nvim ." C-m

tmux new-window -d -t $NAME:2 -n shell -c $DIR
tmux send-keys -t $NAME:2 "cd $DIR && clear" C-m

tmux new-window -d -t $NAME:3 -n bespin -c $DIR
tmux send-keys -t $NAME:3 "cd $DIR && clear && ssh bespin" C-m
tmux send-keys -t $NAME:3 "cd /www/bc_utils && clear" C-m

tmux select-window -t $NAME:1
tmux attach -t $NAME
