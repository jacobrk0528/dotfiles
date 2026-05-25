#!/bin/bash

SLEEP_TIME=.5

# bc utils logs
ghostty --title=bc_utils_log -e bash -c "ssh -t bespin 'tail -f /var/log/bc_cron.log'; echo 'Command exited. Press enter to close.'; read" &
sleep $SLEEP_TIME

# narsil logs
ghostty --title=narsil_log -e bash -c "ssh -t dagobah 'tail -f /var/log/narsil.log'; echo 'Command exited. Press enter to close.'; read" &
