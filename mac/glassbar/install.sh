#!/usr/bin/env bash
# Build GlassBar into ~/Applications/GlassBar.app and (re)start it as a
# LaunchAgent so it runs at login. Re-run after editing GlassBar.swift.
set -euo pipefail

SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP="$HOME/Applications/GlassBar.app"
LABEL="com.jkrebs.glassbar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "🔨 Building GlassBar..."
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/GlassBar" "$SRC_DIR/GlassBar.swift"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$LABEL</string>
    <key>CFBundleName</key><string>GlassBar</string>
    <key>CFBundleExecutable</key><string>GlassBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- No Dock icon or menu bar; it's a background panel -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" >/dev/null

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$APP/Contents/MacOS/GlassBar</string></array>
    <key>RunAtLoad</key><true/>
    <!-- Restart it if it crashes, but not after a clean quit -->
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "✅ GlassBar running (logs: log stream --process GlassBar)"
