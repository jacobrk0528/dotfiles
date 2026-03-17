#!/usr/bin/env bash

DIR="$HOME/Documents/TrinityRoad/local-git/celebrimbor"
NAME="celebrimbor"

tmux new-session -d -s $NAME

tmux new-window -t $NAME:1
tmux send-keys -t $NAME:1 "cd $DIR" C-m
tmux send-keys -t $NAME:1 "nvim ." C-m

tmux new-window -t $NAME:2
tmux send-keys -t $NAME:2 "cd $DIR && clear" C-m

tmux new-window -t $NAME:3
tmux send-keys -t $NAME:3 "cd $DIR && clear && ssh dagobah" C-m
tmux send-keys -t $NAME:3 "cd /www/services/celebrimbor && clear" C-m

tmux select-window -t $NAME:1
tmux attach -t $NAME
