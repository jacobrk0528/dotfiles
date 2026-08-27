#!/usr/bin/env python3
"""Summarizes hypr/scripts/ptt-dictate's Gemini usage log and projects a
monthly cost from however much trial usage has been logged so far."""
import json
import os
from datetime import datetime, timezone

USAGE_LOG = os.path.expanduser("~/.local/share/ptt-dictate/usage.jsonl")


def main():
    if not os.path.exists(USAGE_LOG):
        print(f"No usage log yet at {USAGE_LOG}")
        return

    records = []
    with open(USAGE_LOG) as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))

    if not records:
        print("Usage log is empty.")
        return

    ok = [r for r in records if "cost_usd" in r]
    errors = [r for r in records if "error" in r]

    total_cost = sum(r["cost_usd"] for r in ok)
    total_in = sum(r["input_tokens"] for r in ok)
    total_out = sum(r["output_tokens"] for r in ok)

    timestamps = [datetime.fromisoformat(r["ts"]) for r in records]
    first, last = min(timestamps), max(timestamps)
    span_hours = max((last - first).total_seconds() / 3600, 0.01)

    print(f"Dictations logged:     {len(records)}  ({len(ok)} ok, {len(errors)} errors)")
    print(f"Time span:             {first.isoformat()}  ->  {last.isoformat()}  ({span_hours:.2f} hours)")
    print(f"Total input tokens:    {total_in:,}")
    print(f"Total output tokens:   {total_out:,}")
    print(f"Total cost so far:     ${total_cost:.4f}")
    if ok:
        print(f"Avg cost / dictation:  ${total_cost / len(ok):.6f}")

    hourly_rate = total_cost / span_hours
    print()
    print(f"Projected cost/day (at this rate, {span_hours:.1f}h sample): ${hourly_rate * 24:.4f}")
    print(f"Projected cost/month (30 days):                             ${hourly_rate * 24 * 30:.2f}")

    if errors:
        print()
        print(f"{len(errors)} calls failed and fell back to the local regex pipeline (not counted in cost).")


if __name__ == "__main__":
    main()
