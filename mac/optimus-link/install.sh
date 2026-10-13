#!/usr/bin/env bash
# (Re)start optimus-link as a LaunchAgent so it runs at login. Re-run after
# editing the script. Logs: ~/Library/Logs/optimus-link.log
set -euo pipefail

SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LABEL="com.jkrebs.optimus-link"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/optimus-link.log"

chmod +x "$SRC_DIR/optimus-link"
mkdir -p "$HOME/.local/bin"
ln -sfn "$SRC_DIR/optimus-link" "$HOME/.local/bin/optimus-link"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>/bin/zsh</string><string>$SRC_DIR/optimus-link</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
# bootout returns before the old instance is fully torn down; bootstrapping
# too early fails with "5: Input/output error", so wait for it to disappear.
for _ in {1..50}; do
    launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break
    sleep 0.1
done
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "✅ optimus-link running (status: optimus-link status)"
