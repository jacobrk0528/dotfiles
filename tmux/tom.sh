#!/usr/bin/env bash

DIR="/home/jkrebs/Documents/TrinityRoad/local-git/TomBombadil"
NAME="tom"

cd $DIR
tmux new-session -d -s $NAME

tmux new-window -t $NAME:0
tmux send-keys -t $NAME:0 "cd $DIR" C-m
tmux send-keys -t $NAME:0 "opencode" C-m

tmux new-window -t $NAME:1
tmux send-keys -t $NAME:1 "cd $DIR" C-m
tmux send-keys -t $NAME:1 "nvim ." C-m

tmux new-window -t $NAME:2
tmux send-keys -t $NAME:2 "cd $DIR && clear" C-m

tmux new-window -t $NAME:3
tmux send-keys -t $NAME:3 "cd $DIR && clear && ssh dagobah" C-m
tmux send-keys -t $NAME:3 "cd /www/services/TomBombadil && clear" C-m

tmux new-window -t $NAME:9
tmux send-keys -t $NAME:9 "cd $DIR && clear" C-m
tmux send-keys -t $NAME:9 "bun run dev" C-m

tmux select-window -t $NAME:1
tmux attach -t $NAME
