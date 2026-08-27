#!/usr/bin/env bash
# Install the Quickshell greetd greeter into /etc/greetd.
#
#   sudo ~/dotfiles/scripts/install-greeter.sh
#
# This copies files only. It deliberately does NOT enable or start greetd, and
# does not touch getty@tty1 — flipping the login over is a separate, reversible
# step you take once you have looked at the result:
#
#   sudo systemctl enable greetd.service
#
# To undo, from a TTY (Ctrl-Alt-F2 if the greeter fails on boot):
#
#   sudo systemctl disable --now greetd.service
#   sudo systemctl start getty@tty1.service
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "run with sudo" >&2
    exit 1
fi

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ETC=/etc/greetd
GREETER="$ETC/quickshell-greeter"

for tool in greetd Hyprland qs; do
    command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done

if [ ! -f "$DOTFILES/quickshell-greeter/Colors.qml" ]; then
    echo "Colors.qml missing — run quickshell/scripts/apply-theme first" >&2
    exit 1
fi

install -d -m 755 "$ETC"
install -m 644 "$DOTFILES/greetd/config.toml"   "$ETC/config.toml"
install -m 644 "$DOTFILES/greetd/hyprland.conf" "$ETC/hyprland.conf"
install -m 755 "$DOTFILES/greetd/greeter-session" "$ETC/greeter-session"

rm -rf "$GREETER"
install -d -m 755 "$GREETER"
for f in "$DOTFILES"/quickshell-greeter/*.qml "$DOTFILES"/quickshell-greeter/qmldir; do
    install -m 644 "$f" "$GREETER/"
done

# The greeter user cannot read /home, so the wallpaper is copied in rather than
# referenced. Extension is cosmetic; Qt sniffs the format from the content.
wallpaper=$(python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1]))["path"])' \
    "$DOTFILES/hypr/wallpaper.json" 2>/dev/null || true)

if [ -n "$wallpaper" ] && [ -r "$wallpaper" ]; then
    install -m 644 "$wallpaper" "$GREETER/wallpaper.png"
    echo "wallpaper: $wallpaper"
else
    echo "wallpaper: none found, greeter falls back to a flat background" >&2
fi

# Writable HOME for the greeter: its passwd home is `/`.
install -d -o greeter -g greeter -m 700 /var/lib/greetd

# Hyprland needs the seat's input devices. logind grants those to the session
# it opens for `greeter`, but the `input` group is the reliable fallback on
# setups where it does not.
if ! id -nG greeter | tr ' ' '\n' | grep -qx input; then
    usermod -aG input greeter
    echo "added greeter to the input group"
fi

echo
echo "installed. Nothing has been enabled."
echo "Review, then:  sudo systemctl enable greetd.service  (takes effect next boot)"
