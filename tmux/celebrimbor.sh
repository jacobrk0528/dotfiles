#!/usr/bin/env bash

DIR="/home/jkrebs/Documents/TrinityRoad/local-git/celebrimbor"
NAME="celebrimbor"
SOURCE="source venv/bin/activate"

cd $DIR
# new-session lands its window on the ambient base-index (1 here), so pin it to
# the index this layout wants instead of assuming base-index 0.
tmux new-session -d -s $NAME -n claude -c $DIR
tmux move-window -d -s $NAME:^ -t $NAME:0 2>/dev/null

tmux send-keys -t $NAME:0 "cd $DIR && $SOURCE && clear" C-m
tmux send-keys -t $NAME:0 "claude" C-m

tmux new-window -d -t $NAME:1 -n nvim -c $DIR
tmux send-keys -t $NAME:1 "cd $DIR" C-m
tmux send-keys -t $NAME:1 "$SOURCE && clear" C-m
tmux send-keys -t $NAME:1 "nvim ." C-m

tmux new-window -d -t $NAME:2 -n shell -c $DIR
tmux send-keys -t $NAME:2 "cd $DIR && $SOURCE && clear" C-m

tmux new-window -d -t $NAME:3 -n dagobah -c $DIR
tmux send-keys -t $NAME:3 "cd $DIR && clear && ssh dagobah" C-m
tmux send-keys -t $NAME:3 "cd /www/services/celebrimbor && clear" C-m

# api on the left pane, celery worker on the right; addressed via the window's
# active pane so this does not depend on pane-base-index either.
tmux new-window -d -t $NAME:9 -n services -c $DIR
tmux send-keys -t $NAME:9 "cd $DIR && venv/bin/python -m uvicorn api.main:app --host 0.0.0.0 --port 8001 --reload" C-m
tmux split-window -h -t $NAME:9 -c $DIR
tmux send-keys -t $NAME:9 "cd $DIR && venv/bin/python -m celery -A celery_app.celery worker --loglevel=INFO" C-m

tmux select-window -t $NAME:1
tmux attach -t $NAME
