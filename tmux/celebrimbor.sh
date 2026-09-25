#!/usr/bin/env bash
# FastAPI + Celery NetSuite product-data reconciliation service.
. "$(dirname "$(readlink -f "$0")")/builder_lib.sh"

b_init celebrimbor "$HOME/Documents/TrinityRoad/local-git/celebrimbor"
b_venv

b_cd 0
b_send 0 "claude"

b_window 1 nvim
b_cd 1
b_send 1 "nvim ."

b_window 2 shell
b_cd 2

# dagobah is production. The wheeljack staging box is driven by `make deploy`
# from here, so it does not get a window.
b_ssh 3 dagobah dagobah /www/services/celebrimbor

# api on the left pane, celery worker on the right. Beat is deliberately not
# run locally -- the nightly user-notes loop only matters on the deployed box.
b_window 9 services
b_send 9 "cd $DIR && $VENV_PY -m uvicorn api.main:app --host 0.0.0.0 --port 8001 --reload"
tmux split-window -h -t "$NAME:9" -c "$DIR"
b_send 9 "cd $DIR && $VENV_PY -m celery -A celery_app.celery worker --loglevel=INFO"

b_finish 1
