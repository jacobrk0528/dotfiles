#!/usr/bin/env bash

mem_info=$(free -m | awk '/^Mem:/ {print $2, $3, $6, $7}')
read -r total_mib used_mib buff_mib avail_mib <<< "$mem_info"

total_gb=$(awk "BEGIN {printf \"%.1f\", $total_mib / 1024}")
used_gb=$(awk "BEGIN {printf \"%.1f\", $used_mib / 1024}")
buff_gb=$(awk "BEGIN {printf \"%.1f\", $buff_mib / 1024}")
avail_gb=$(awk "BEGIN {printf \"%.1f\", $avail_mib / 1024}")

usage_pct=$(( 100 * used_mib / total_mib ))

# Color coding
if [ "$usage_pct" -lt 70 ]; then
  mem_color="<span color=\"#50fa7b\">${usage_pct}%</span>"
elif [ "$usage_pct" -lt 85 ]; then
  mem_color="<span color=\"#f1fa8c\">${usage_pct}% (High)</span>"
else
  mem_color="<span color=\"#ff5555\">${usage_pct}% (CRITICAL)</span>"
fi

# Top 3 Memory processes
top_mem=$(ps -eo comm,pmem --sort=-pmem | awk 'NR>1 && $1!="ps" && $1!="awk" {printf "  %-16s %5.1f%%\n", $1, $2}' | head -n 3)

header="System Memory (${total_gb} GB)"
usage_sec=$(printf "Usage Breakdown:\n  Used:      %6s GB (%b)\n  Available: %6s GB\n  Buff/Cache:%6s GB" "$used_gb" "$mem_color" "$avail_gb" "$buff_gb")
proc_sec=$(printf "Top Memory Processes:\n%s" "$top_mem")

tooltip=$(printf "%s\n\n%b\n\n%s" "$header" "$usage_sec" "$proc_sec")
text="${usage_pct}%"

jq -c -n --arg text "$text" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'
