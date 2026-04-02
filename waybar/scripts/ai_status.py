#!/usr/bin/env python3
import subprocess
import json
import os

def get_processes():
    try:
        # Get pids of opencode and claude
        # We use pgrep -a to filter out helper processes
        output = subprocess.check_output(["pgrep", "-a", "opencode|claude"], text=True)
    except subprocess.CalledProcessError:
        return []
    
    procs = []
    for line in output.strip().split("\n"):
        parts = line.split(" ", 1)
        if len(parts) < 2: continue
        pid, cmd = parts
        
        # Filter out helper processes for opencode
        if "opencode" in cmd:
            if "run " in cmd or "x " in cmd or "telemetry" in cmd:
                continue
        
        # Filter for claude
        if "claude" in cmd:
             # Add specific filters if needed, usually 'claude' is the main process
             pass
             
        procs.append((pid, "opencode" if "opencode" in cmd else "claude"))
    return procs

def check_activity(procs):
    if not procs: return 0, 0, []
    
    pids = [p[0] for p in procs]
    
    # Use top to get current CPU usage for these PIDs
    # top -b -n 1 -p pid1,pid2...
    try:
        top_cmd = ["top", "-b", "-n", "1", "-p", ",".join(pids)]
        output = subprocess.check_output(top_cmd, text=True)
        
        # Parse top output
        working = 0
        waiting = 0
        details = []
        
        lines = output.strip().split("\n")
        start_parsing = False
        for line in lines:
            if "PID" in line and "USER" in line:
                start_parsing = True
                continue
            if start_parsing:
                parts = line.split()
                if len(parts) > 8:
                    pid = parts[0]
                    cpu = float(parts[8])
                    state = parts[7]
                    
                    # Find which tool this is
                    tool = next((p[1] for p in procs if p[0] == pid), "AI")
                    
                    is_working = cpu > 2.0 or state == "R"
                    if is_working:
                        working += 1
                    else:
                        waiting += 1
                    
                    details.append(f"{tool} ({pid}): {'Working' if is_working else 'Waiting'} (CPU: {cpu}%)")
        
        return working, waiting, details
    except Exception as e:
        return 0, len(procs), [f"Error: {str(e)}"]

def main():
    procs = get_processes()
    if not procs:
        print(json.dumps({})) # Empty output hides the module
        return

    working, waiting, details = check_activity(procs)
    
    # 󰚩 (Robot) or 󱐋 (Sparkle) or 󰧑 (Claude-ish)
    # We'll use 󰚩 for AI generally
    icon = "󰚩"
    
    text = f"{icon} {working}/{working+waiting}"
    tooltip = "\n".join(details)
    
    status_class = "working" if working > 0 else "idle"
    
    print(json.dumps({
        "text": text,
        "tooltip": tooltip,
        "class": status_class,
        "alt": status_class
    }))

if __name__ == "__main__":
    main()
