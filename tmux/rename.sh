#!/usr/bin/env bash

# Get the PID of the foreground process in the current tmux pane
child_pid=$(pgrep -P $(tmux display-message -p "#{pane_pid}"))

# Get the full command of the foreground process
input_command=$(ps -o command= -p $child_pid)

# Extract the actual command (ignoring sudo if present)
command_name=$(echo "$input_command" | awk '
{
    for(i=1; i<=NF; i++) {
        if ($i == "sudo") continue;
        if ($i == "ssh") {
            print $(i+1);
            exit;
        }
        print $i;
        exit;
    }
}')


# Output the extracted command name
echo "$command_name"

