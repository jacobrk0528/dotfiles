#!/usr/bin/env bash

if [ -z "$1" ]; then
  echo "Usage: ~/.tmux/load_or_create.sh <session_name>"
  exit 1
fi

INPUT_NAME=$1

EXISTING_SESSION=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -i "^$INPUT_NAME$" | head -n 1)

if [ -n "$EXISTING_SESSION" ]; then
  tmux attach -t "$EXISTING_SESSION"
else
  if [ -f ~/.tmux/"$INPUT_NAME".sh ]; then
    ~/.tmux/"$INPUT_NAME".sh
  else
    tmux new-session -s "$INPUT_NAME" -n "$INPUT_NAME"
  fi
fi
