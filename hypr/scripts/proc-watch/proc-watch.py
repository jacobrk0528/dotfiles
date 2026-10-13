#!/usr/bin/env python3
"""Watch for runaway processes and raise a desktop notification.

Samples /proc every INTERVAL seconds and alerts when:
  - one process averages >= CPU_PCT of a core over CPU_WINDOW seconds
    (a browser tab spinning, a stuck loop),
  - one process's resident memory passes MEM_GB (and again each time it
    doubles from there),
  - the CPU die (k10temp Tctl) stays >= TEMP_C for TEMP_WINDOW seconds, naming
    the busiest processes,
  - the NVIDIA GPU stays >= GPU_TEMP_C, or its VRAM stays >= VRAM_PCT full,
    naming the processes holding VRAM (high GPU *utilization* is not alerted:
    it is what a local-model run is supposed to look like),
  - available system memory stays under MEM_AVAIL_PCT, naming the biggest
    processes,
  - an NVMe drive stays >= NVME_C,
  - a mounted disk reaches DISK_PCT full (re-alerts every DISK_COOLDOWN).

Alerts go through notify-send, so they land in the quickshell notification
center. CPU and per-process memory alerts carry an "End process" action. Each process
alerts at most once per COOLDOWN for each kind.

Written for the 2026-09 case of a Google Cloud Console tab (Dark Reader, see
the `browser` comment in hypr/hyprland.lua) growing to 9 GB at 100% CPU
without anyone noticing until the CPU temperature did.

Run by proc-watch.service. `--test` uses tiny thresholds for trying it out.
"""

import argparse
import glob
import os
import signal
import subprocess
import sys
import threading
import time
from collections import deque

INTERVAL = 10          # seconds between samples
CPU_PCT = 80           # percent of one core
CPU_WINDOW = 120       # seconds the average must hold
MEM_GB = 6
TEMP_C = 85
TEMP_WINDOW = 60
COOLDOWN = 30 * 60
GPU_TEMP_C = 85
VRAM_PCT = 95
VRAM_WINDOW = 120
MEM_AVAIL_PCT = 10     # alert when less than this share of RAM is available
MEM_AVAIL_WINDOW = 60
NVME_C = 75            # drives report a ~82C "high" mark
DISK_PCT = 90
DISK_COOLDOWN = 6 * 3600

# Expected to peg a core for minutes at a time.
IGNORE = {"rustc", "cc1", "cc1plus", "ld", "ld.lld", "ffmpeg", "makepkg"}

CLK_TCK = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
UID = os.getuid()


def read_procs():
    """{pid: (starttime, cpu_ticks, rss_bytes, comm)} for every process."""
    procs = {}
    for path in glob.glob("/proc/[0-9]*"):
        pid = int(path[6:])
        try:
            with open(f"{path}/stat") as f:
                stat = f.read()
            with open(f"{path}/statm") as f:
                rss = int(f.read().split()[1]) * PAGE
        except (OSError, IndexError, ValueError):
            continue  # exited mid-read
        # comm is in parens and may itself contain spaces or parens
        comm = stat[stat.index("(") + 1 : stat.rindex(")")]
        fields = stat[stat.rindex(")") + 2 :].split()
        # fields[0] is state (field 3); utime/stime are fields 14/15, starttime 22
        ticks = int(fields[11]) + int(fields[12])
        procs[pid] = (int(fields[19]), ticks, rss, comm)
    return procs


def describe(pid, comm):
    """Human name: browser renderers become "Chrome tab" etc."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            raw = f.read()
    except OSError:
        raw = b""
    # Split on spaces too: Chromium-based browsers (Brave) rewrite their argv
    # into one space-joined string
    args = raw.replace(b"\0", b" ").split()
    exe = os.path.basename(args[0].decode(errors="replace")) if args else comm
    browser = {"chrome": "Chrome", "brave": "Brave", "chromium": "Chromium"}.get(exe)
    if browser and b"--type=renderer" in args:
        return f"{browser} tab", f"Shift+Esc in {browser} shows which tab"
    if browser and b"--type=gpu-process" in args:
        return f"{browser} GPU process", ""
    return exe or comm, ""


def owner(pid):
    try:
        return os.stat(f"/proc/{pid}").st_uid
    except OSError:
        return None


def cpu_temp():
    for name_file in glob.glob("/sys/class/hwmon/hwmon*/name"):
        with open(name_file) as f:
            if f.read().strip() != "k10temp":
                continue
        base = os.path.dirname(name_file)
        try:
            with open(f"{base}/temp1_input") as f:
                return int(f.read()) / 1000
        except OSError:
            return None
    return None


def nvme_temp():
    """Hottest NVMe composite temperature, or None."""
    best = None
    for name_file in glob.glob("/sys/class/hwmon/hwmon*/name"):
        try:
            with open(name_file) as f:
                if f.read().strip() != "nvme":
                    continue
            with open(os.path.dirname(name_file) + "/temp1_input") as f:
                t = int(f.read()) / 1000
        except (OSError, ValueError):
            continue
        best = t if best is None else max(best, t)
    return best


def nvidia(query, section="gpu"):
    """Rows of `nvidia-smi --query-<section>=<query>` as lists of strings, or
    None when there is no NVIDIA driver."""
    try:
        out = subprocess.run(
            ["nvidia-smi", f"--query-{section}={query}", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    return [[c.strip() for c in line.split(",")] for line in out.stdout.splitlines() if line.strip()]


def gpu_stats():
    """(temp C, VRAM used MiB, VRAM total MiB) or None."""
    rows = nvidia("temperature.gpu,memory.used,memory.total")
    try:
        t, used, total = rows[0]
        return float(t), float(used), float(total)
    except (TypeError, IndexError, ValueError):
        return None


def vram_users():
    """Top VRAM holders as "name 1.2 GB" strings."""
    rows = nvidia("pid,used_memory", "compute-apps") or []
    apps = []
    for row in rows:
        try:
            apps.append((float(row[1]), describe(int(row[0]), "?")[0]))
        except (IndexError, ValueError):
            continue
    return [f"{n} {u / 1024:.1f} GB" for u, n in sorted(apps, reverse=True)[:3]]


def mem_available():
    """(available bytes, total bytes)."""
    info = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":")
            info[k] = int(v.split()[0]) * 1024
    return info["MemAvailable"], info["MemTotal"]


def disks():
    """{mountpoint: percent full} for each distinct real filesystem."""
    seen, out = set(), {}
    with open("/proc/mounts") as f:
        for line in f:
            _, mnt, fs = line.split()[:3]
            if fs not in ("ext4", "btrfs", "xfs", "f2fs", "zfs"):
                continue
            try:
                st, vfs = os.stat(mnt), os.statvfs(mnt)
            except OSError:
                continue
            if st.st_dev in seen or not vfs.f_blocks:
                continue
            seen.add(st.st_dev)
            out[mnt] = (1 - vfs.f_bavail / vfs.f_blocks) * 100
    return out


class Sustained:
    """True once a condition has held for `window` seconds, then not again
    until `cooldown` has passed."""

    def __init__(self, window, cooldown=COOLDOWN):
        self.window, self.cooldown = window, cooldown
        self.since = None
        self.last = None

    def fire(self, now, active):
        if not active:
            self.since = None
            return False
        self.since = self.since or now
        if now - self.since < self.window:
            return False
        if self.last is not None and now - self.last < self.cooldown:
            return False
        self.last = now
        return True


def gb(n):
    return f"{n / 1024**3:.1f} GB"


def notify(summary, body, urgency="normal", kill=None):
    """Post a notification; with kill=(pid, starttime) it offers "End process"
    and waits for the answer on a thread, re-checking the pid is still the same
    process before signalling it."""
    cmd = ["notify-send", "-a", "Process watch", "-u", urgency]
    if kill:
        cmd += ["-A", "kill=End process", "-w"]
    cmd += [summary, body]
    print(f"alert: {summary} — {body}", flush=True)

    def run():
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=3600).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return
        if kill and out == "kill":
            pid, start = kill
            current = read_procs().get(pid)
            if current and current[0] == start:
                os.kill(pid, signal.SIGTERM)
                print(f"ended {pid} on request", flush=True)

    threading.Thread(target=run, daemon=True).start()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", action="store_true", help="tiny thresholds: 2s samples, 50%% over 6s, 0.5 GB")
    opts = ap.parse_args()

    interval, cpu_pct, cpu_window, mem_gb = INTERVAL, CPU_PCT, CPU_WINDOW, MEM_GB
    gpu_temp_c, vram_pct, mem_avail_pct, nvme_c, disk_pct = GPU_TEMP_C, VRAM_PCT, MEM_AVAIL_PCT, NVME_C, DISK_PCT
    win = {"vram": VRAM_WINDOW, "mem": MEM_AVAIL_WINDOW, "gpu": TEMP_WINDOW, "nvme": TEMP_WINDOW}
    if opts.test:
        interval, cpu_pct, cpu_window, mem_gb = 2, 50, 6, 0.5
        gpu_temp_c, vram_pct, mem_avail_pct, nvme_c, disk_pct = 20, 5, 99, 20, 1
        win = dict.fromkeys(win, 4)

    gpu_hot, vram_full = Sustained(win["gpu"]), Sustained(win["vram"])
    mem_low, nvme_hot = Sustained(win["mem"]), Sustained(win["nvme"])
    disk_full = {}     # mountpoint -> Sustained(0, DISK_COOLDOWN)

    need = max(1, cpu_window // interval)
    history = {}       # (pid, start) -> deque of cpu% samples
    alerted = {}       # (pid, start, kind) -> time of last alert
    mem_mark = {}      # (pid, start) -> RSS level of the last memory alert
    hot_since = None

    prev, prev_t = read_procs(), time.monotonic()
    print(f"watching: cpu>={cpu_pct}% for {cpu_window}s, mem>={mem_gb}GB, temp>={TEMP_C}C, "
          f"gpu>={gpu_temp_c}C, vram>={vram_pct}%, ram avail<{mem_avail_pct}%, nvme>={nvme_c}C, disk>={disk_pct}%",
          flush=True)

    while True:
        time.sleep(interval)
        now = time.monotonic()
        procs = read_procs()
        dt = now - prev_t
        usage = []

        for pid, (start, ticks, rss, comm) in procs.items():
            key = (pid, start)
            before = prev.get(pid)
            if not before or before[0] != start:
                continue  # new, or pid reused
            pct = (ticks - before[1]) / CLK_TCK / dt * 100
            usage.append((pct, pid, comm))
            if comm in IGNORE:
                continue

            h = history.setdefault(key, deque(maxlen=need))
            h.append(pct)

            def due(kind):
                return now - alerted.get((pid, start, kind), -COOLDOWN) >= COOLDOWN

            mine = owner(pid) == UID
            if len(h) == need and sum(h) / need >= cpu_pct and due("cpu"):
                alerted[(pid, start, "cpu")] = now
                name, hint = describe(pid, comm)
                notify(f"{name} is using {sum(h) / need:.0f}% CPU",
                       f"Sustained for {cpu_window // 60 or cpu_window}{' min' if cpu_window >= 60 else 's'} · "
                       f"{gb(rss)} memory · PID {pid}" + (f"\n{hint}" if hint else ""),
                       kill=(pid, start) if mine else None)

            mark = mem_mark.get(key, mem_gb * 1024**3)
            if rss >= mark and (key not in mem_mark or rss >= mark * 2):
                mem_mark[key] = rss
                name, hint = describe(pid, comm)
                notify(f"{name} is using {gb(rss)} of memory",
                       f"{pct:.0f}% CPU right now · PID {pid}" + (f"\n{hint}" if hint else ""),
                       kill=(pid, start) if mine else None)

        temp = cpu_temp()
        if temp is not None and temp >= TEMP_C:
            hot_since = hot_since or now
            if now - hot_since >= TEMP_WINDOW and now - alerted.get("temp", -COOLDOWN) >= COOLDOWN:
                alerted["temp"] = now
                top = sorted(usage, reverse=True)[:3]
                notify(f"CPU at {temp:.0f}°C",
                       "Busiest: " + ", ".join(f"{describe(p, c)[0]} {u:.0f}%" for u, p, c in top),
                       urgency="critical")
        else:
            hot_since = None

        gpu = gpu_stats()
        if gpu:
            g_temp, v_used, v_total = gpu
            if gpu_hot.fire(now, g_temp >= gpu_temp_c):
                users = vram_users()
                notify(f"GPU at {g_temp:.0f}°C", ("Using VRAM: " + ", ".join(users)) if users else "",
                       urgency="critical")
            if vram_full.fire(now, v_used / v_total * 100 >= vram_pct):
                users = vram_users()
                notify(f"GPU memory {v_used / v_total * 100:.0f}% full",
                       f"{v_used / 1024:.1f} of {v_total / 1024:.1f} GB" + (" · " + ", ".join(users) if users else ""))

        avail, total = mem_available()
        if mem_low.fire(now, avail / total * 100 < mem_avail_pct):
            top = sorted(((v[2], p, v[3]) for p, v in procs.items()), reverse=True)[:3]
            notify(f"Only {gb(avail)} of RAM available",
                   "Biggest: " + ", ".join(f"{describe(p, c)[0]} {gb(r)}" for r, p, c in top),
                   urgency="critical")

        n_temp = nvme_temp()
        if nvme_hot.fire(now, n_temp is not None and n_temp >= nvme_c):
            notify(f"NVMe drive at {n_temp:.0f}°C", "Sustained heavy disk I/O or poor airflow")

        for mnt, pct in disks().items():
            w = disk_full.setdefault(mnt, Sustained(0, DISK_COOLDOWN))
            if w.fire(now, pct >= disk_pct):
                notify(f"{mnt} is {pct:.0f}% full", "Free some space before it fills up")

        # Forget processes that exited
        alive = {(p, v[0]) for p, v in procs.items()}
        for d in (history, mem_mark):
            for k in [k for k in d if k not in alive]:
                del d[k]
        for k in [k for k in alerted if k != "temp" and (k[0], k[1]) not in alive]:
            del alerted[k]

        prev, prev_t = procs, now


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
