#!/usr/bin/env python3
"""Push-to-talk / toggle dictation daemon.

Loads a Whisper model once and stays resident. Controlled by signals
(see ptt_dictate.sh): SIGUSR1 starts recording, SIGUSR2 stops it,
transcribes, and types the result into whatever window is focused via
`wtype`. SIGRTMIN toggles recording on/off (start if idle, stop if
recording) for a press-once-to-start/press-again-to-stop key.
"""
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

import numpy as np
import sounddevice as sd
from faster_whisper import WhisperModel

# Whisper already infers comma/period/question-mark/etc. from speech
# cadence reasonably well, so we don't override those (saying "period"
# to mean the word vs. the punctuation is ambiguous from text alone).
# Kept here are only commands for words rarely used literally in normal
# sentences (parens, colon) plus things Whisper has no way to infer
# (literal newlines). Longer phrases first so "new paragraph" matches
# before "new line" would (wrongly) swallow just "new".
# "OPEN"/"CLOSE" sentinels mark directional punctuation (no space after
# an opener, no space before a closer) and get resolved after spacing
# cleanup, since "(" and ")" need opposite rules.
_OPEN, _CLOSE = "\x01", "\x02"
VOICE_COMMANDS = [
    ("new paragraph", "\n\n"),
    ("new line", "\n"),
    ("newline", "\n"),
    ("open paren", _OPEN + "("),
    ("open parenthesis", _OPEN + "("),
    ("open parentheses", _OPEN + "("),
    ("close paren", _CLOSE + ")"),
    ("close parenthesis", _CLOSE + ")"),
    ("close parentheses", _CLOSE + ")"),
    ("colon", ":"),
]
_COMMAND_RE = re.compile(
    r"\b(" + "|".join(re.escape(p) for p, _ in VOICE_COMMANDS) + r")\b",
    re.IGNORECASE,
)
_COMMAND_MAP = {p: r for p, r in VOICE_COMMANDS}
# No space before punctuation/closers ("hello :" -> "hello:")
_SPACE_BEFORE_PUNCT_RE = re.compile(r"\s+(:|" + _CLOSE + r")")
# No space after openers
_SPACE_AFTER_OPEN_RE = re.compile(_OPEN + r"(.)\s+")
# Collapse whitespace around inserted newlines
_SPACE_AROUND_NL_RE = re.compile(r"[ \t]*\n[ \t]*")


def apply_voice_commands(text):
    text = _COMMAND_RE.sub(lambda m: _COMMAND_MAP[m.group(1).lower()], text)
    text = _SPACE_AFTER_OPEN_RE.sub(r"\1", text)
    text = _SPACE_BEFORE_PUNCT_RE.sub(r"\1", text)
    text = text.replace(_OPEN, "").replace(_CLOSE, "")
    text = _SPACE_AROUND_NL_RE.sub("\n", text)
    text = re.sub(r"[ \t]{2,}", " ", text)
    return text.strip()


_NUM_WORDS = {
    w: i + 1
    for i, w in enumerate(
        "one two three four five six seven eight nine ten eleven twelve "
        "thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty".split()
    )
}
# A line that starts with "new line"/"new paragraph" is a plausible list
# item if it also starts with a number: "1 xyz", "1) xyz", "one: xyz".
_LIST_ITEM_RE = re.compile(
    r"^\s*(\d{1,2}|" + "|".join(_NUM_WORDS) + r")\b[.:)]?\s+(.*)$",
    re.IGNORECASE,
)


# Any number token, anywhere in the text (not just line-start) - used to
# spot spoken lists like "1 xyz 2 abc 3 def" with no "new line" between
# items.
_NUM_TOKEN_RE = re.compile(
    r"\b(\d{1,2}|" + "|".join(_NUM_WORDS) + r")\b", re.IGNORECASE
)


def _preceding_word(text, pos):
    j = pos
    while j > 0 and text[j - 1] in " \t":
        j -= 1
    end = j
    while j > 0 and text[j - 1].isalpha():
        j -= 1
    return text[j:end]


# A real dictated list item ("1 xyz", "2 abc") is short. If the next
# expected number doesn't show up within this many words, it's more
# likely an incidental number deep in the current item's own content
# ("2 I bought a shirt and it turns out it was actually the wrong size
# so I had to drive back to the mall and get 3 different ones instead")
# than a real next marker - so the run stops there instead of grabbing
# a coincidental later match.
MAX_MARKER_GAP_WORDS = 12


def _word_gap(text, start, end):
    return len(text[start:end].split())


def explode_inline_lists(text):
    """Insert a line break before each marker of an inline 1,2,3,...
    sequence. Requires the run to start at 1 (not just any two
    consecutive numbers) since ordinary sentences rarely enumerate
    starting from one - "grab 2 or 3 apples" won't trigger, but
    "1 xyz 2 abc" will. Also skips any number directly preceded by the
    word "number" ("line number two") - that's a reference, not a list
    marker, and without this a phrase like "number one ... number two"
    scattered through unrelated text would falsely read as a list."""
    all_matches = list(_NUM_TOKEN_RE.finditer(text))
    matches = [m for m in all_matches if _preceding_word(text, m.start()).lower() != "number"]
    values = [
        int(m.group(0)) if m.group(0).isdigit() else _NUM_WORDS[m.group(0).lower()]
        for m in matches
    ]

    runs = []
    i = 0
    while i < len(matches):
        if values[i] == 1:
            j = i
            while (
                j + 1 < len(matches)
                and values[j + 1] == values[j] + 1
                and _word_gap(text, matches[j].end(), matches[j + 1].start()) <= MAX_MARKER_GAP_WORDS
            ):
                j += 1
            if j > i:
                runs.append((i, j))
                i = j + 1
                continue
        i += 1
    if not runs:
        return text

    split_at = sorted({matches[k].start() for start, end in runs for k in range(start, end + 1)}, reverse=True)
    for pos in split_at:
        left = pos
        while left > 0 and text[left - 1] in " \t":
            left -= 1
        if left == 0:
            continue
        text = text[:left] + "\n" + text[pos:]
    return text


def format_lists(text):
    lines = text.split("\n")
    matches = [_LIST_ITEM_RE.match(line) for line in lines]
    matched_idx = [i for i, m in enumerate(matches) if m is not None]
    # Only treat as a list if at least two lines look like list items - a
    # single leading number is more likely just "3 dogs ran by" than a list.
    if len(matched_idx) < 2:
        return text

    # Number every line in the span from the first to the last recognized
    # marker, not just the ones that matched: a homophone miss ("two" ->
    # "to") means a real list item can slip through without matching, but
    # once we know it's a list, position tells us the number anyway.
    start, end = matched_idx[0], matched_idx[-1]
    first_token = matches[start].group(1)
    first_num = int(first_token) if first_token.isdigit() else _NUM_WORDS[first_token.lower()]

    for offset, i in enumerate(range(start, end + 1)):
        num = first_num + offset
        m = matches[i]
        rest = m.group(2) if m is not None else lines[i]
        lines[i] = f"{num}) {rest}"
    return "\n".join(lines)


# --- Gemini-based formatting (trial: local regex pipeline was too fragile
# on some phrasing; testing whether a hosted model does noticeably better).
# Falls back to the regex pipeline above if no key is set or the call
# fails, so dictation never breaks because of network/API issues. ---

GEMINI_MODEL = "gemini-flash-lite-latest"
GEMINI_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
# https://ai.google.dev/pricing - re-check if pricing changes; these are
# only used to *estimate* cost from token counts for the usage log, not
# billed by us.
GEMINI_PRICE_IN_PER_M = 0.25
GEMINI_PRICE_OUT_PER_M = 1.50

USAGE_LOG = os.path.expanduser("~/.local/share/ptt-dictate/usage.jsonl")

GEMINI_SYSTEM_PROMPT = """You clean up raw speech-to-text output before it is typed into a text field. Follow these rules exactly:

1. Add correct punctuation and capitalization. Fix obvious sentence boundaries. Always capitalize the first letter of the output.
2. If the speaker is dictating an enumerated list (saying a sequence of numbers like "one... two... three..." as item markers), format it as a numbered list: each item on its own line, prefixed with the actual digit and a closing paren, like "1) item text". Never output a literal "N" - always substitute the real number.
3. Do NOT treat a number as a list marker if it's a normal reference, e.g. "line number two", "call me at 3pm", "grab 2 apples", or an incidental number mentioned deep inside an item's own content. Leave those as plain text, unchanged.
4. If the speaker says "new line" or "newline", replace it with an actual line break (remove those words). If they say "new paragraph", insert a blank line (two line breaks).
5. If the speaker says "open quote" / "close quote" or "quotation mark", replace with a literal " character (positioned correctly, no stray spaces next to it). Same for "open paren(thesis/theses)" / "close paren(thesis/theses)" -> ( and ).
6. Preserve every other word the speaker said. Only add punctuation/capitalization/line breaks/the substitutions above - never rephrase, remove, or add words.
7. Output ONLY the final text. No explanations, no quotes around your answer, no markdown fences, nothing else.

Example 1:
Input: 1 xyz 2 abc 3 hjk
Output:
1) xyz
2) abc
3) hjk

Example 2:
Input: this is test number three of a list colon one testing line number one two testing line number two three testing line number three
Output:
This is test number three of a list:
1) testing line number one
2) testing line number two
3) testing line number three

Example 3:
Input: please call me at 2 or 3 pm
Output:
Please call me at 2 or 3 pm.

Example 4:
Input: first line new line second line
Output:
First line
Second line

Example 5:
Input: open quote hello world close quote
Output:
"hello world\""""


def log_usage(record):
    os.makedirs(os.path.dirname(USAGE_LOG), exist_ok=True)
    with open(USAGE_LOG, "a") as f:
        f.write(json.dumps(record) + "\n")


def gemini_format(raw_text):
    """Returns formatted text, or None if unavailable (missing key,
    network error, unexpected response) so the caller can fall back to
    the local regex pipeline."""
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        return None

    body = json.dumps({
        "system_instruction": {"parts": {"text": GEMINI_SYSTEM_PROMPT}},
        "contents": [{"role": "user", "parts": [{"text": raw_text}]}],
        "generationConfig": {"temperature": 0.1},
    }).encode()
    req = urllib.request.Request(
        GEMINI_URL,
        data=body,
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
    )

    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read())
    except Exception as e:
        log_usage({
            "ts": datetime.now(timezone.utc).isoformat(),
            "raw_text": raw_text,
            "error": str(e),
        })
        return None
    latency = time.time() - t0

    try:
        formatted = data["candidates"][0]["content"]["parts"][0]["text"].strip()
        usage = data.get("usageMetadata", {})
        in_tok = usage.get("promptTokenCount", 0)
        out_tok = usage.get("candidatesTokenCount", 0)
        cost = in_tok / 1_000_000 * GEMINI_PRICE_IN_PER_M + out_tok / 1_000_000 * GEMINI_PRICE_OUT_PER_M
    except Exception as e:
        log_usage({
            "ts": datetime.now(timezone.utc).isoformat(),
            "raw_text": raw_text,
            "error": f"unexpected response shape: {e}",
        })
        return None

    log_usage({
        "ts": datetime.now(timezone.utc).isoformat(),
        "raw_text": raw_text,
        "formatted_text": formatted,
        "input_tokens": in_tok,
        "output_tokens": out_tok,
        "cost_usd": cost,
        "latency_s": round(latency, 3),
    })
    return formatted


WHISPER_RATE = 16000
MODEL_SIZE = "small.en"
MIC_NAME_MATCH = "fifine"
PID_FILE = os.path.expanduser("~/.cache/ptt-dictate.pid")


def find_mic_device(name_match):
    for i, d in enumerate(sd.query_devices()):
        if d["max_input_channels"] > 0 and name_match.lower() in d["name"].lower():
            return i
    return None


MIC_DEVICE = find_mic_device(MIC_NAME_MATCH)
MIC_RATE = int(sd.query_devices(MIC_DEVICE)["default_samplerate"]) if MIC_DEVICE is not None else WHISPER_RATE


def resample(audio, orig_rate, target_rate):
    if orig_rate == target_rate:
        return audio
    duration = len(audio) / orig_rate
    target_len = int(duration * target_rate)
    orig_x = np.linspace(0, duration, len(audio), endpoint=False)
    target_x = np.linspace(0, duration, target_len, endpoint=False)
    return np.interp(target_x, orig_x, audio).astype(np.float32)

model = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")

state = {
    "recording": False,
    "frames": [],
    "stream": None,
    "mode": "dictate",
    "mic_rate": WHISPER_RATE,
}
lock = threading.Lock()

CORRECTIONS_FILE = os.path.expanduser("~/.config/ptt-dictate/corrections.json")


def load_corrections():
    try:
        with open(CORRECTIONS_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_corrections(corrections):
    os.makedirs(os.path.dirname(CORRECTIONS_FILE), exist_ok=True)
    with open(CORRECTIONS_FILE, "w") as f:
        json.dump(corrections, f, indent=2, sort_keys=True)


def apply_corrections(text, corrections):
    """Exact-phrase corrections learned via teach mode - whole-word,
    case-insensitive, longest phrases first so a learned multi-word
    phrase isn't shadowed by a shorter one."""
    for heard, correct in sorted(corrections.items(), key=lambda kv: -len(kv[0])):
        text = re.sub(r"\b" + re.escape(heard) + r"\b", correct, text, flags=re.IGNORECASE)
    return text


# Terminal emulators bind paste to ctrl+shift+v (ctrl+v is reserved for
# shell/program use); GUI apps (Slack, browsers, etc.) use plain ctrl+v.
TERMINAL_WINDOW_CLASSES = {
    "com.mitchellh.ghostty", "kitty", "alacritty", "foot", "wezterm",
    "xterm", "gnome-terminal-server", "org.gnome.console", "konsole",
    "tilix", "terminator", "urxvt",
}


def is_terminal_focused():
    try:
        result = subprocess.run(
            ["hyprctl", "-j", "activewindow"], capture_output=True, text=True, timeout=2, check=False,
        )
        window = json.loads(result.stdout)
        return window.get("class", "").lower() in TERMINAL_WINDOW_CLASSES
    except Exception:
        return False


def type_text(text):
    """Typing '\\n' as a synthetic keypress (even Shift+Return) can race
    with the focused app and occasionally fire as a plain Return, which
    submits the message instead of inserting a line break - happens
    rarely but is a real failure mode when it does. Pasting sidesteps it
    entirely: paste never sends a Return keydown, so embedded newlines
    just land as literal line breaks, and it can't accidentally submit
    anything, in any app. The previous clipboard contents are restored
    afterward so this doesn't clobber your normal copy/paste."""
    try:
        old_clip = subprocess.run(
            ["wl-paste", "--no-newline"], capture_output=True, timeout=2, check=False,
        ).stdout
    except Exception:
        old_clip = None

    # Every subprocess call here has an explicit timeout: this all runs
    # inside a signal handler on the daemon's one thread, so if any of
    # these processes ever hangs (a wl-copy that doesn't fork/detach as
    # expected, a compositor hiccup, etc.) it would otherwise freeze the
    # daemon indefinitely - it stays "running" per systemd but stops
    # responding to every future keypress until manually restarted. That
    # happened once already from an untimed wl-copy call.
    try:
        subprocess.run(["wl-copy"], input=(text + " ").encode(), timeout=5, check=False)
    except subprocess.TimeoutExpired:
        notify("⚠ clipboard copy timed out, dictation not typed", "critical")
        return
    time.sleep(0.05)  # give the compositor a moment to register the new clipboard offer
    paste_keys = ["-M", "ctrl", "-M", "shift", "-k", "v", "-m", "shift", "-m", "ctrl"] \
        if is_terminal_focused() else ["-M", "ctrl", "-k", "v", "-m", "ctrl"]
    try:
        subprocess.run(["wtype", *paste_keys], timeout=5, check=False)
    except subprocess.TimeoutExpired:
        notify("⚠ paste keystroke timed out", "critical")

    if old_clip is not None:
        def restore():
            time.sleep(1.0)
            subprocess.run(["wl-copy"], input=old_clip, timeout=5, check=False)
        threading.Thread(target=restore, daemon=True).start()


def run_safe(cmd, timeout=5, **kwargs):
    """subprocess.run with a mandatory timeout - see the big comment in
    type_text for why: any untimed call here runs on the daemon's one
    signal-handling thread, and a hang there freezes ALL future dictation
    until a manual restart, silently (the process still looks 'active')."""
    try:
        return subprocess.run(cmd, timeout=timeout, check=False, **kwargs)
    except subprocess.TimeoutExpired:
        return None


STATE_FILE = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ptt-dictate.state"
)


def set_state(name):
    """Publish what the daemon is doing for the shell's bar indicator.

    This replaces the transient 'listening'/'transcribing' notifications:
    a status the shell can render is less intrusive than a popup per phrase.
    Written atomically so the shell never reads a half-written file.
    """
    try:
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"state": name}, f)
        os.replace(tmp, STATE_FILE)
    except OSError:
        pass


def notify(msg, urgency="low", persist=False):
    timeout = "0" if persist else "1500"
    try:
        subprocess.run(
            ["notify-send", "-a", "ptt-dictate", "-u", urgency, "-t", timeout, msg],
            timeout=5, check=False,
        )
    except subprocess.TimeoutExpired:
        pass


def audio_callback(indata, frames, time_info, status):
    with lock:
        if state["recording"]:
            state["frames"].append(indata.copy())


def start_recording(signum, frame, mode="dictate"):
    with lock:
        if state["recording"]:
            return
        # Re-resolve the mic fresh each time rather than trusting the
        # index captured at daemon startup - a USB replug/re-enumeration
        # can change or briefly invalidate it, and opening a stale device
        # index raises PortAudioError("Device unavailable"), which used to
        # crash the whole daemon (an uncaught exception in a signal
        # handler kills the process).
        device = find_mic_device(MIC_NAME_MATCH)
        if device is None:
            device, rate = None, WHISPER_RATE
        else:
            rate = int(sd.query_devices(device)["default_samplerate"])
        try:
            stream = sd.InputStream(
                device=device,
                samplerate=rate,
                channels=1,
                dtype="float32",
                callback=audio_callback,
            )
            stream.start()
        except Exception as e:
            notify(f"⚠ mic error, couldn't start recording: {e}", "critical")
            return
        state["frames"] = []
        state["recording"] = True
        state["mode"] = mode
        state["stream"] = stream
        state["mic_rate"] = rate
    set_state("teaching" if mode == "teach" else "listening")


def teach_start(signum, frame):
    start_recording(signum, frame, mode="teach")


def handle_teach(heard):
    """Prompts (via wofi) for the correct spelling of what Whisper just
    heard, and saves the mapping so future transcriptions get it right -
    both as an exact-phrase correction and as a recognition hint fed to
    Whisper. Runs in a background thread since it blocks on user input."""
    notify(f'🎓 heard "{heard}" — type correct spelling in the popup...', persist=True)

    def prompt():
        try:
            result = subprocess.run(
                ["wofi", "--dmenu", "--prompt", f"Spelling for \"{heard}\":"],
                capture_output=True, text=True, timeout=120,
            )
        except Exception as e:
            run_safe(["makoctl", "dismiss", "--all"])
            notify(f"teach failed: {e}", urgency="critical")
            return
        run_safe(["makoctl", "dismiss", "--all"])
        correct = result.stdout.strip()
        if not correct:
            notify("teach cancelled")
            return
        corrections = load_corrections()
        corrections[heard.lower()] = correct
        save_corrections(corrections)
        notify(f'learned: "{heard}" -> "{correct}"')

    threading.Thread(target=prompt, daemon=True).start()


def stop_recording(signum, frame):
    with lock:
        if not state["recording"]:
            return
        state["recording"] = False
        stream = state["stream"]
        frames = state["frames"]
        mode = state["mode"]
        mic_rate = state["mic_rate"]
        state["stream"] = None
    if stream is not None:
        stream.stop()
        stream.close()
    run_safe(["makoctl", "dismiss", "--all"])

    if not frames:
        return
    audio = np.concatenate(frames, axis=0).flatten()
    duration = len(audio) / mic_rate
    if duration < 0.3:
        return

    # An uncaught exception here would kill the whole daemon (it's running
    # inside a signal handler) - catch broadly and surface it as a
    # notification instead, so a transcription/formatting hiccup doesn't
    # take down dictation entirely until the next auto-restart.
    try:
        set_state("transcribing")
        audio = resample(audio, mic_rate, WHISPER_RATE)
        corrections = load_corrections()
        initial_prompt = ", ".join(corrections.values()) if corrections else None
        segments, _ = model.transcribe(audio, language="en", vad_filter=True, initial_prompt=initial_prompt)
        text = "".join(seg.text for seg in segments).strip()

        if not text:
            notify("(nothing heard)")
            return

        if mode == "teach":
            handle_teach(text)
            return

        text = apply_corrections(text, corrections)
        formatted = gemini_format(text)
        if formatted is None:
            formatted = format_lists(explode_inline_lists(apply_voice_commands(text)))
        type_text(formatted)
    except Exception as e:
        notify(f"⚠ dictation failed: {e}", "critical")
    finally:
        set_state("idle")


def toggle_recording(signum, frame):
    with lock:
        recording = state["recording"]
    if recording:
        stop_recording(signum, frame)
    else:
        start_recording(signum, frame)


def main():
    os.makedirs(os.path.dirname(PID_FILE), exist_ok=True)
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    signal.signal(signal.SIGUSR1, start_recording)
    signal.signal(signal.SIGUSR2, stop_recording)
    signal.signal(signal.SIGRTMIN, toggle_recording)
    signal.signal(signal.SIGRTMIN + 1, teach_start)

    if MIC_DEVICE is None:
        notify(f"⚠ mic matching '{MIC_NAME_MATCH}' not found, using default input", "critical")
    else:
        formatter = "Gemini" if os.environ.get("GEMINI_API_KEY") else "local regex"
        notify(f"push-to-talk dictation ready ({formatter} formatting)")
    set_state("idle")
    while True:
        signal.pause()


if __name__ == "__main__":
    main()
