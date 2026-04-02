#!/bin/bash

WALL="$HOME/.config/hypr/wallpapers/minimal_slate.png"

if [ ! -f "$WALL" ]; then
    echo "Error: Wallpaper not found at $WALL"
    exit 1
fi

if ! pgrep -x "hyprpaper" > /dev/null; then
    echo "Starting hyprpaper..."
    hyprpaper &
    sleep 2
fi

hyprctl hyprpaper preload "$WALL"
hyprctl hyprpaper wallpaper ",$WALL"

sleep 1
hyprctl hyprpaper unload all
