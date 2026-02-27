#!/bin/bash

WORKSPACE="special:logs"
SLEEP_TIME=.5

# bc utils logs
hyprctl dispatch exec "[workspace $WORKSPACE] ghostty --title=bc_utils_log -e bash -c \"ssh -t bespin 'tail -f /var/log/bc_cron.log'; echo 'Command exited. Press enter to close.'; read\""
sleep $SLEEP_TIME

# narsil logs
hyprctl dispatch exec "[workspace $WORKSPACE] ghostty --title=narsil_log -e bash -c \"ssh -t dagobah 'tail -f /var/log/narsil.log'; echo 'Command exited. Press enter to close.'; read\""
sleep $SLEEP_TIME
