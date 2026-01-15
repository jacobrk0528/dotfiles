#!/usr/bin/env bash

DIR="/home/jacob/Documents/TrinityRoad/local-git/narsil"
NAME="narsil"
SOURCE="nix-shell"

cd $DIR
tmux new-session -d -s $NAME

tmux new-window -t $NAME:1
tmux send-keys -t $NAME:1 "cd $DIR" C-m
tmux send-keys -t $NAME:1 "$SOURCE && clear" C-m
tmux send-keys -t $NAME:1 "nvim ." C-m

tmux new-window -t $NAME:2
tmux send-keys -t $NAME:2 "cd $DIR && $SOURCE && clear" C-m

tmux new-window -t $NAME:3
tmux send-keys -t $NAME:3 "cd $DIR && clear && ssh dagobah" C-m
tmux send-keys -t $NAME:3 "cd /www/services/narsil && clear" C-m

tmux new-window -t $NAME:0
tmux send-keys -t $NAME:0 "cd $DIR && clear && opencode" C-m

tmux select-window -t $NAME:1
tmux attach -t $NAME
