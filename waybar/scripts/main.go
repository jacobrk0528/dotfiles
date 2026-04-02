package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type WaybarOutput struct {
	Text    string `json:"text"`
	Tooltip string `json:"tooltip"`
	Class   string `json:"class"`
	Alt     string `json:"alt"`
}

type ProcInfo struct {
	PID  string
	Tool string
}

func getProcesses() []ProcInfo {
	cmd := exec.Command("pgrep", "-a", "opencode|claude")
	output, _ := cmd.Output()
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")

	var procs []ProcInfo
	for _, line := range lines {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, " ", 2)
		if len(parts) < 2 {
			continue
		}
		pid := parts[0]
		cmdline := parts[1]

		// Filter out helper processes
		if strings.Contains(cmdline, "run ") || strings.Contains(cmdline, "x ") || strings.Contains(cmdline, "telemetry") {
			continue
		}

		tool := "opencode"
		if strings.Contains(cmdline, "claude") {
			tool = "claude"
		}

		procs = append(procs, ProcInfo{PID: pid, Tool: tool})
	}
	return procs
}

func getTmuxPanes() map[string]string {
	panes := make(map[string]string)
	cmd := exec.Command("tmux", "list-panes", "-a", "-F", "#{pane_pid} #{session_name}")
	output, err := cmd.Output()
	if err != nil {
		return panes
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) >= 2 {
			panes[fields[0]] = fields[1]
		}
	}
	return panes
}

func getParentPID(pid string) string {
	data, err := ioutil.ReadFile(fmt.Sprintf("/proc/%s/stat", pid))
	if err != nil {
		return ""
	}
	fields := strings.Fields(string(data))
	if len(fields) < 4 {
		return ""
	}
	return fields[3]
}

func getContext(pid string, panes map[string]string) string {
	curr := pid
	for curr != "" && curr != "0" && curr != "1" {
		if session, ok := panes[curr]; ok {
			return session
		}
		curr = getParentPID(curr)
	}

	// Fallback to CWD
	cwd, err := os.Readlink(fmt.Sprintf("/proc/%s/cwd", pid))
	if err != nil {
		return pid // absolute fallback to pid if all else fails
	}
	return filepath.Base(cwd)
}

func main() {
	procs := getProcesses()
	if len(procs) == 0 {
		return
	}

	panes := getTmuxPanes()
	working := 0
	waiting := 0
	var details []string

	// Simple activity detection:
	// Sample 1
	type sample struct {
		total uint64
		state string
	}
	samples1 := make(map[string]sample)
	for _, p := range procs {
		data, err := ioutil.ReadFile(fmt.Sprintf("/proc/%s/stat", p.PID))
		if err != nil {
			continue
		}
		f := strings.Fields(string(data))
		if len(f) > 14 {
			u, _ := strconv.ParseUint(f[13], 10, 64)
			s, _ := strconv.ParseUint(f[14], 10, 64)
			samples1[p.PID] = sample{total: u + s, state: f[2]}
		}
	}

	time.Sleep(200 * time.Millisecond)

	// Sample 2
	for _, p := range procs {
		data, err := ioutil.ReadFile(fmt.Sprintf("/proc/%s/stat", p.PID))
		if err != nil {
			continue
		}
		f := strings.Fields(string(data))
		if len(f) > 14 {
			u, _ := strconv.ParseUint(f[13], 10, 64)
			s, _ := strconv.ParseUint(f[14], 10, 64)
			total2 := u + s
			state2 := f[2]

			s1, exists := samples1[p.PID]
			if !exists {
				continue
			}
			diff := total2 - s1.total

			// If CPU ticks changed or it's currently Running
			isWorking := diff > 0 || state2 == "R"

			statusStr := "Ready"
			if isWorking {
				working++
				statusStr = "Working"
			} else {
				waiting++
			}
			details = append(details, fmt.Sprintf("%s (%s): %s", p.Tool, getContext(p.PID, panes), statusStr))
		}
	}

	output := WaybarOutput{
		Text:    fmt.Sprintf("󰚩  %d/%d", working, working+waiting),
		Tooltip: strings.Join(details, "\n"),
		Class:   "ready",
		Alt:     "ready",
	}
	if working > 0 {
		output.Class = "working"
		output.Alt = "working"
	}

	jsonOutput, _ := json.Marshal(output)
	fmt.Println(string(jsonOutput))
}
