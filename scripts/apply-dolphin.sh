#!/usr/bin/env bash
# Install the Dolphin config into ~/.config.
#
# These are copied, not symlinked: KDE saves config atomically (write temp,
# rename over), which replaces a symlink with a regular file the moment you
# change any setting in the GUI. Copying keeps the repo as the seed and lets
# Dolphin own the live file.
#
# Re-run after editing dolphin/dolphinrc, or after apply-theme regenerates
# dolphin/kdeglobals. Your GUI tweaks are NOT copied back — fold anything you
# want to keep into dolphin/dolphinrc.

set -euo pipefail

DOTS="$HOME/dotfiles"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}"

if pgrep -x dolphin >/dev/null; then
    echo "dolphin is running; it will overwrite these on exit. Close it first." >&2
    exit 1
fi

for f in dolphinrc kdeglobals; do
    src="$DOTS/dolphin/$f"
    [ -f "$src" ] || { echo "missing $src" >&2; exit 1; }

    if [ -e "$DEST/$f" ] && ! cmp -s "$src" "$DEST/$f"; then
        cp -a "$DEST/$f" "$DEST/$f.backup"
        echo "backed up existing $f -> $f.backup"
    fi

    cp "$src" "$DEST/$f"
    echo "installed $f"
done

echo
echo "Dolphin panels (F11 info, F4 terminal, F3 split) are stored in the window"
echo "state, not in dolphinrc — press them once and Dolphin remembers."
