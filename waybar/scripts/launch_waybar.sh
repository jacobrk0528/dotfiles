#!/usr/bin/env bash
pkill -x waybar 2>/dev/null || true
pkill -f hypr_ipc_proxy.py 2>/dev/null || true
sleep 0.2

python3 /home/jkrebs/dotfiles/waybar/scripts/hypr_ipc_proxy.py &
sleep 0.3

export HYPRLAND_INSTANCE_SIGNATURE="proxy_${HYPRLAND_INSTANCE_SIGNATURE}"
exec waybar "$@"
