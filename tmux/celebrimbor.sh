#!/usr/bin/env bash

DIR="/home/jkrebs/Documents/TrinityRoad/local-git/celebrimbor"
NAME="celebrimbor"
SOURCE="source venv/bin/activate"

cd $DIR
tmux new-session -d -s $NAME

tmux new-window -t $NAME:0
tmux send-keys -t $NAME:0 "cd $DIR && $SOURCE && clear" C-m
tmux send-keys -t $NAME:0 "claude" C-m

tmux new-window -t $NAME:1
tmux send-keys -t $NAME:1 "cd $DIR" C-m
tmux send-keys -t $NAME:1 "$SOURCE && clear" C-m
tmux send-keys -t $NAME:1 "nvim ." C-m

tmux new-window -t $NAME:2
tmux send-keys -t $NAME:2 "cd $DIR && $SOURCE && clear" C-m

tmux new-window -t $NAME:3
tmux send-keys -t $NAME:3 "cd $DIR && clear && ssh dagobah" C-m
tmux send-keys -t $NAME:3 "cd /www/services/celebrimbor && clear" C-m

tmux new-window -t $NAME:9
tmux split-window -t $NAME:9 -h
tmux send-keys -t $NAME:9.0 "cd $DIR && venv/bin/python -m uvicorn api.main:app --host 0.0.0.0 --port 8001 --reload" C-m
tmux send-keys -t $NAME:9.1 "cd $DIR && venv/bin/python -m celery -A celery_app.celery worker --loglevel=INFO" C-m

tmux select-window -t $NAME:1
tmux attach -t $NAME

