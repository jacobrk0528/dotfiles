#!/usr/bin/env python3
"""Record CPU/GPU temperatures, load and the busiest processes once a second,
so a warm spell can be traced back to what caused it.

  sysmon record                 run the recorder (sysmon.service does this)
  sysmon report [--since 2h]    per-minute temps with the top processes
  sysmon report --hot           only the minutes that reached 70C
  sysmon at 14:53               what was running around a moment

Times are "30m", "2h", "1d" (ago), "14:53" (today) or "2026-10-13 14:53".

Each sample holds k10temp Tctl (what the bar shows) and both CCD sensors, busy%
per CCD, load, top core clock, available RAM, the hottest NVMe, the GPU, and the
top processes by CPU over that second with the core each last ran on. The
9950X3D's two CCDs heat separately, so one hot CCD with the other idle points at
a single runaway thread.

Written for 2026-10: xdg-desktop-portal-hyprland spun one core at 100% for 18h
after a stuck screencast session, holding Tctl in the high 70s.

Data lives in $XDG_DATA_HOME/sysmon/sysmon.db (SQLite) and is kept KEEP_DAYS.
"""

import argparse
import glob
import os
import re
import signal
import sqlite3
import subprocess
import sys
import time
from datetime import datetime

INTERVAL = 1           # seconds between samples
TOP_N = 8              # processes stored per sample
MIN_PROC_PCT = 1.0     # below this a process isn't worth a row
GPU_EVERY = 5          # nvidia-smi is a subprocess spawn: reuse its reading
COMMIT_EVERY = 10      # samples per transaction
KEEP_DAYS = 14
HOT_C = 70             # the bar turns yellow here

CLK_TCK = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
DB = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                  "sysmon", "sysmon.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS samples (
    ts REAL PRIMARY KEY,
    tctl REAL, tccd1 REAL, tccd2 REAL,
    cpu REAL, ccd1 REAL, ccd2 REAL,      -- busy %, whole CPU and per CCD
    load1 REAL, freq_mhz REAL, mem_avail_gb REAL, nvme REAL,
    gpu_temp REAL, gpu_util REAL, gpu_w REAL, gpu_fan REAL, vram_gb REAL
);
CREATE TABLE IF NOT EXISTS procs (
    ts REAL, pid INTEGER, name TEXT,
    cpu REAL,                             -- percent of one core
    rss_mb REAL, core INTEGER
);
CREATE INDEX IF NOT EXISTS procs_ts ON procs (ts);
"""


# --- sampling ----------------------------------------------------------------

def read_procs():
    """{pid: (starttime, cpu_ticks, rss_bytes, comm, last_core)}."""
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
        comm = stat[stat.index("(") + 1 : stat.rindex(")")]
        fields = stat[stat.rindex(")") + 2 :].split()
        # fields[0] is field 3 (state): utime/stime 14/15, starttime 22, processor 39
        procs[pid] = (int(fields[19]), int(fields[11]) + int(fields[12]), rss, comm, int(fields[36]))
    return procs


def describe(pid, comm):
    """Same naming as proc-watch: browser renderers become "Brave tab"."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            raw = f.read()
    except OSError:
        raw = b""
    args = raw.replace(b"\0", b" ").split()
    exe = os.path.basename(args[0].decode(errors="replace")) if args else comm
    browser = {"chrome": "Chrome", "brave": "Brave", "chromium": "Chromium"}.get(exe)
    if browser and b"--type=renderer" in args:
        return f"{browser} tab"
    if browser and b"--type=gpu-process" in args:
        return f"{browser} GPU"
    # Interpreters: name the script, not "python3"
    if exe.startswith(("python", "bun", "node", "bash")) and len(args) > 1:
        script = next((a for a in args[1:] if not a.startswith(b"-")), None)
        if script:
            return f"{exe} {os.path.basename(script.decode(errors='replace'))}"
    return exe or comm


def ccd_groups():
    """CPU numbers per CCD, in order, from which CPUs share an L3."""
    groups = {}
    for d in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cache/index3/shared_cpu_list"):
        cpu = int(re.search(r"cpu(\d+)/cache", d).group(1))
        with open(d) as f:
            groups.setdefault(f.read().strip(), []).append(cpu)
    return sorted((sorted(g) for g in groups.values()), key=lambda g: g[0])


def read_cpu_times():
    """{cpu number or None for the total: (busy, total)} jiffies."""
    out = {}
    with open("/proc/stat") as f:
        for line in f:
            if not line.startswith("cpu"):
                break
            name, *vals = line.split()
            vals = [int(v) for v in vals[:8]]
            idle = vals[3] + vals[4]  # idle + iowait
            out[None if name == "cpu" else int(name[3:])] = (sum(vals) - idle, sum(vals))
    return out


def busy_pct(prev, cur, cpus):
    busy = sum(cur[c][0] - prev[c][0] for c in cpus)
    total = sum(cur[c][1] - prev[c][1] for c in cpus)
    return busy / total * 100 if total else 0.0


def hwmon(name):
    """{label: celsius} for the hwmon chip called `name` (first match)."""
    for name_file in glob.glob("/sys/class/hwmon/hwmon*/name"):
        with open(name_file) as f:
            if f.read().strip() != name:
                continue
        out = {}
        for inp in glob.glob(os.path.dirname(name_file) + "/temp*_input"):
            try:
                with open(inp) as f:
                    val = int(f.read()) / 1000
                with open(inp.replace("_input", "_label")) as f:
                    label = f.read().strip()
            except (OSError, ValueError):
                continue
            out[label] = val
        return out
    return {}


def nvme_temp():
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


def max_freq_mhz():
    best = 0
    for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"):
        try:
            with open(p) as f:
                best = max(best, int(f.read()))
        except (OSError, ValueError):
            pass
    return best / 1000 or None


def mem_avail_gb():
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) / 1024**2
    return None


def gpu():
    """(temp, util %, watts, fan %, VRAM GB), Nones when there is no NVIDIA GPU."""
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=temperature.gpu,utilization.gpu,power.draw,fan.speed,memory.used",
             "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=5)
        vals = [float(v) for v in out.stdout.splitlines()[0].split(",")]
        vals[4] /= 1024
        return tuple(vals)
    except (OSError, subprocess.TimeoutExpired, IndexError, ValueError):
        return (None,) * 5


def connect(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript(SCHEMA)
    return db


def record(path):
    db = connect(path)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))  # so `finally` commits
    groups = ccd_groups()
    ccd1, ccd2 = (groups + [[], []])[:2]
    print(f"recording to {path}: CCD1 cpus {ccd1}, CCD2 cpus {ccd2}", flush=True)

    prev_procs, prev_cpu, prev_t = read_procs(), read_cpu_times(), time.monotonic()
    gpu_vals, n = (None,) * 5, 0
    next_tick = time.monotonic() + INTERVAL
    try:
        while True:
            time.sleep(max(0, next_tick - time.monotonic()))
            next_tick += INTERVAL
            now, ts = time.monotonic(), round(time.time(), 1)
            procs, cpu = read_procs(), read_cpu_times()
            dt = now - prev_t

            usage, seen = [], 0.0
            for pid, (start, ticks, rss, comm, core) in procs.items():
                before = prev_procs.get(pid)
                # A new process (or reused pid) did all its work since the last sample
                spent = ticks - before[1] if before and before[0] == start else ticks
                pct = spent / CLK_TCK / dt * 100
                seen += pct
                if pct >= MIN_PROC_PCT:
                    usage.append((pct, pid, rss, comm, core))
            # Processes that started and exited between samples (compiler jobs)
            # never show up in /proc for us: book their CPU as one row
            total = sum(cpu[c][0] - prev_cpu[c][0] for c in cpu if c is not None) / CLK_TCK / dt * 100
            if total - seen >= 10:
                usage.append((total - seen, 0, 0, "(exited between samples)", -1))
            usage.sort(reverse=True)

            if n % GPU_EVERY == 0:
                gpu_vals = gpu()
            k10 = hwmon("k10temp")
            db.execute("INSERT OR REPLACE INTO samples VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
                ts, k10.get("Tctl"), k10.get("Tccd1"), k10.get("Tccd2"),
                busy_pct(prev_cpu, cpu, [None]),
                busy_pct(prev_cpu, cpu, ccd1) if ccd1 else None,
                busy_pct(prev_cpu, cpu, ccd2) if ccd2 else None,
                os.getloadavg()[0], max_freq_mhz(), mem_avail_gb(), nvme_temp(), *gpu_vals))
            db.executemany("INSERT INTO procs VALUES (?,?,?,?,?,?)", [
                (ts, pid, describe(pid, comm), round(pct, 1), round(rss / 1024**2), core)
                for pct, pid, rss, comm, core in usage[:TOP_N]])

            n += 1
            if n % COMMIT_EVERY == 0:
                db.commit()
            if n % 3600 == 0:
                cutoff = time.time() - KEEP_DAYS * 86400
                db.execute("DELETE FROM samples WHERE ts < ?", (cutoff,))
                db.execute("DELETE FROM procs WHERE ts < ?", (cutoff,))
                db.commit()
            prev_procs, prev_cpu, prev_t = procs, cpu, now
    finally:
        db.commit()
        db.close()


# --- reading -----------------------------------------------------------------

def parse_when(s):
    """Epoch seconds for "30m"/"2h"/"1d" ago, "14:53" today, or a full date."""
    m = re.fullmatch(r"(\d+(?:\.\d+)?)([smhd])", s)
    if m:
        return time.time() - float(m.group(1)) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)]
    for fmt in ("%H:%M", "%H:%M:%S"):
        try:
            t = datetime.strptime(s, fmt).time()
            return datetime.combine(datetime.now().date(), t).timestamp()
        except ValueError:
            pass
    try:
        return datetime.fromisoformat(s).timestamp()
    except ValueError:
        sys.exit(f"can't read time {s!r}: use 30m, 2h, 14:53 or 2026-10-13 14:53")


def fmt(v, width=5, digits=0):
    return f"{v:{width}.{digits}f}" if v is not None else " " * (width - 1) + "-"


def top_procs(db, start, end, limit=3):
    """[(name, avg % of a core over the span, most-used core)] by total CPU."""
    secs = db.execute("SELECT count(*) FROM samples WHERE ts >= ? AND ts < ?", (start, end)).fetchone()[0] or 1
    rows = db.execute("""
        SELECT name, sum(cpu) / ?, (SELECT core FROM procs p2 WHERE p2.ts >= ? AND p2.ts < ?
                                    AND p2.name = p.name GROUP BY core ORDER BY count(*) DESC LIMIT 1)
        FROM procs p WHERE ts >= ? AND ts < ? GROUP BY name ORDER BY sum(cpu) DESC LIMIT ?""",
        (secs, start, end, start, end, limit)).fetchall()
    return rows


def report(db, since, until, bucket, hot):
    rows = db.execute("""
        SELECT CAST(ts / ? AS INT) * ? AS b, min(tctl), avg(tctl), max(tctl), max(tccd1), max(tccd2),
               avg(ccd1), avg(ccd2), max(gpu_temp), count(*)
        FROM samples WHERE ts >= ? AND ts < ? GROUP BY b ORDER BY b""",
        (bucket, bucket, since, until)).fetchall()
    if not rows:
        print("no samples in that range (is sysmon.service running?)")
        return
    print(f"{'time':<11} {'Tctl min/avg/max':>17} {'CCD1':>5} {'CCD2':>5} {'busy1':>5} {'busy2':>5} "
          f"{'GPU':>4}  top processes (% of a core, @core)")
    shown = 0
    for b, tmin, tavg, tmax, c1, c2, u1, u2, g, cnt in rows:
        if hot and (tmax or 0) < HOT_C:
            continue
        shown += 1
        mark = "*" if (tmax or 0) >= HOT_C else " "
        procs = ", ".join(f"{n} {c:.0f}%@{core}" for n, c, core in top_procs(db, b, b + bucket))
        stamp = datetime.fromtimestamp(b).strftime("%m-%d %H:%M" if bucket >= 60 else "%H:%M:%S")
        print(f"{stamp:<11}{mark}{fmt(tmin)}/{fmt(tavg, 4)}/{fmt(tmax, 4)}  {fmt(c1)} {fmt(c2)} "
              f"{fmt(u1)}% {fmt(u2, 4)}% {fmt(g, 4)}  {procs}")
    if hot and not shown:
        print(f"Tctl never reached {HOT_C}°C in that range")


def at(db, when, window):
    start, end = when - window, when + window
    s = db.execute("""SELECT count(*), avg(tctl), max(tctl), avg(tccd1), avg(tccd2), avg(cpu), avg(ccd1), avg(ccd2),
                             avg(load1), avg(freq_mhz), avg(mem_avail_gb), avg(nvme), avg(gpu_temp), avg(gpu_util),
                             avg(gpu_w), avg(vram_gb)
                      FROM samples WHERE ts >= ? AND ts < ?""", (start, end)).fetchone()
    if not s[0]:
        print("no samples around then")
        return
    _, tctl, tmax, c1, c2, cpu, u1, u2, load, freq, mem, nvme, gt, gu, gw, vram = s
    print(f"{datetime.fromtimestamp(start):%Y-%m-%d %H:%M:%S} to {datetime.fromtimestamp(end):%H:%M:%S}"
          f" ({s[0]} samples)")
    print(f"  Tctl {fmt(tctl, 0)}°C (max {fmt(tmax, 0)}) · CCD1 {fmt(c1, 0)}°C · CCD2 {fmt(c2, 0)}°C")
    print(f"  busy {fmt(cpu, 0)}% · CCD1 {fmt(u1, 0)}% · CCD2 {fmt(u2, 0)}% · load {fmt(load, 0, 2)}"
          f" · top clock {fmt(freq, 0)} MHz")
    print(f"  RAM available {fmt(mem, 0, 1)} GB · NVMe {fmt(nvme, 0)}°C")
    print(f"  GPU {fmt(gt, 0)}°C · {fmt(gu, 0)}% · {fmt(gw, 0)} W · VRAM {fmt(vram, 0, 1)} GB")
    print("  top processes (avg % of a core, usual core):")
    for name, c, core in top_procs(db, start, end, 10):
        print(f"    {c:6.1f}%  @{core:<3} {name}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--db", default=DB)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("record", help="sample once a second into the database")
    r = sub.add_parser("report", help="per-minute temperatures and top processes")
    r.add_argument("--since", default="1h")
    r.add_argument("--until", default=None)
    r.add_argument("--bucket", type=int, default=60, help="seconds per row")
    r.add_argument("--hot", action="store_true", help=f"only rows that reached {HOT_C}°C")
    a = sub.add_parser("at", help="what was running around a moment")
    a.add_argument("when")
    a.add_argument("--window", type=int, default=30, help="seconds either side")
    opts = ap.parse_args()

    if opts.cmd == "record":
        record(opts.db)
        return
    if not os.path.exists(opts.db):
        sys.exit(f"no data yet at {opts.db}: start it with `systemctl --user enable --now sysmon`")
    db = sqlite3.connect(f"file:{opts.db}?mode=ro", uri=True)
    if opts.cmd == "report":
        report(db, parse_when(opts.since), parse_when(opts.until) if opts.until else time.time(),
               opts.bucket, opts.hot)
    else:
        at(db, parse_when(opts.when), opts.window)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
