#!/bin/bash
# Switch default sink to $1, or toggle mute if it's already the active sink.

TARGET_SINK=$1

if [ -z "$TARGET_SINK" ]; then
    echo "Usage: $0 <sink_name>"
    exit 1
fi

CURRENT_SINK=$(pactl get-default-sink)

if [ "$CURRENT_SINK" = "$TARGET_SINK" ]; then
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    exit 0
fi

# Bluetooth sinks are named bluez_output.AA_BB_CC_DD_EE_FF.<profile> - if the
# device isn't connected yet, its sink won't exist in pactl's list. Connect
# first (and wait for the sink to appear) so one keypress does both steps.
if [[ "$TARGET_SINK" =~ ^bluez_output\.([0-9A-F_]+)\. ]]; then
    MAC=$(echo "${BASH_REMATCH[1]}" | tr '_' ':')

    if ! pactl list short sinks | grep -q "$TARGET_SINK"; then
        bluetoothctl connect "$MAC"

        for _ in $(seq 1 20); do
            pactl list short sinks | grep -q "$TARGET_SINK" && break
            sleep 0.5
        done
    fi
fi

pactl set-default-sink "$TARGET_SINK"
