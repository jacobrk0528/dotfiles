#!/usr/bin/env bash
# (Re)start `sync-status --notify` as a LaunchAgent, so a sync conflict pops up
# a notification. Re-run after moving the dotfiles. Logs:
# ~/Library/Logs/sync-notify.log
set -euo pipefail

LABEL="com.jkrebs.sync-notify"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/sync-notify.log"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$HOME/.local/bin/sync-status</string><string>--notify</string></array>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST

DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
# Same wait as optimus-link/install.sh: bootstrapping before the old instance
# is gone fails with "5: Input/output error".
for _ in {1..50}; do
    launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break
    sleep 0.1
done
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "✅ sync-notify running"
