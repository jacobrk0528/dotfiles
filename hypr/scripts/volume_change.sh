#!/bin/bash

STEP=${1:-5}
DIRECTION=$2

CURRENT_VOL=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100 + 0.5)}')

if [ "$DIRECTION" = "up" ]; then
    NEW_VOL=$(( ((CURRENT_VOL + STEP + (STEP / 2)) / STEP) * STEP ))
    [ $NEW_VOL -gt 100 ] && NEW_VOL=100
elif [ "$DIRECTION" = "down" ]; then
    NEW_VOL=$(( ((CURRENT_VOL - STEP + (STEP / 2)) / STEP) * STEP ))
    [ $NEW_VOL -lt 0 ] && NEW_VOL=0
else
    echo "Usage: $0 <step_amount> [up|down]"
    exit 1
fi

TARGET_VOL=$(awk -v vol="$NEW_VOL" 'BEGIN {print vol / 100}')

wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "$TARGET_VOL"
