#!/usr/bin/env bash
# Mirrors the currently active Hyprland/quickshell wallpaper onto macOS.
# quickshell itself is Wayland-only and can't run here, but the wallpaper
# picker just writes hypr/wallpaper.json (see quickshell/README.md), and that
# file plus hypr/wallpapers/ are tracked in git — so whatever wallpaper is
# active on Linux comes along on the next `git pull` and can be applied here
# with `osascript`.
set -euo pipefail

DOTFILES="$HOME/dotfiles"
WALLPAPER_JSON="$DOTFILES/hypr/wallpaper.json"

command -v jq &> /dev/null || { echo "set-wallpaper: jq is required (brew bundle installs it)" >&2; exit 1; }
[ -f "$WALLPAPER_JSON" ] || { echo "set-wallpaper: $WALLPAPER_JSON not found" >&2; exit 1; }

name=$(basename "$(jq -r '.path' "$WALLPAPER_JSON")")
wallpaper="$DOTFILES/hypr/wallpapers/$name"
[ -f "$wallpaper" ] || { echo "set-wallpaper: $wallpaper not found" >&2; exit 1; }

osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$wallpaper\""
echo "Set wallpaper to $wallpaper"
