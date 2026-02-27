#!/bin/bash

DIR="$HOME/.config/hypr/wallpapers"
RANDOM_WALL=$(find "$DIR" -name "*.png" | shuf -n 1)

if [ -z "$RANDOM_WALL" ]; then
    echo "Error: No wallpapers found in $DIR"
    exit 1
fi

if ! pgrep -x "hyprpaper" > /dev/null; then
    echo "Starting hyprpaper..."
    hyprpaper &
    sleep 2
fi

hyprctl hyprpaper preload "$RANDOM_WALL"
hyprctl hyprpaper wallpaper ",$RANDOM_WALL"

# Give it a moment to apply before unloading others
sleep 1
hyprctl hyprpaper unload all
