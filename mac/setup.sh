#!/usr/bin/env bash

set -e

echo "🍎 Starting macOS Setup..."

DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# 1. Xcode Command Line Tools
if ! xcode-select -p &> /dev/null; then
    echo "🛠️  Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "   Follow the prompt, then re-run this script."
    exit 1
fi

# 2. Homebrew
if ! command -v brew &> /dev/null; then
    echo "🍺 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for Apple Silicon
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

# 3. Install packages from Brewfile
echo "📦 Installing packages from Brewfile..."
# HOMEBREW_ACCEPT_EULA (not ACCEPT_EULA) is what msodbcsql18/mssql-tools18
# actually check; without it their formulas block on a raw STDIN.gets prompt
# that brew bundle's output buffering can make look hung.
export HOMEBREW_ACCEPT_EULA=Y

# Homebrew refuses to install from a tap it hasn't been told to trust yet.
# Tap and trust ours explicitly before `brew bundle` pulls from them, or
# every formula/cask in the Brewfile silently fails.
for tap in microsoft/mssql-release manaflow-ai/cmux koekeishiya/formulae; do
    brew tap "$tap"
    brew trust "$tap"
done

brew bundle --file="$DOTFILES_DIR/mac/Brewfile"

# Tailscale is often installed manually outside Homebrew (e.g. Mac App Store,
# direct pkg); installing the cask on top of that triggers a conflict dialog.
# Only install it if it's not already present.
if [ ! -d "/Applications/Tailscale.app" ]; then
    echo "📡 Installing Tailscale..."
    brew install --cask tailscale-app
else
    echo "📡 Tailscale already installed, skipping."
fi

# 4. Homelab CA cert — trusts self-signed certs served by internal
# services (e.g. home.internal). Fetched insecurely since, on a fresh
# machine, nothing trusts it yet; that's expected for a first bootstrap.
echo "🔒 Installing homelab CA certificate..."
CERT_TMP="$(mktemp -t homelabCA).crt"
if curl -fsSk https://home.internal/homelabCA.crt -o "$CERT_TMP"; then
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_TMP"
else
    echo "   Couldn't reach home.internal (not on the home network?) — skipping."
fi
rm -f "$CERT_TMP"

# 5. Enable Services
echo "⚙️  Starting services..."
# No local postgres/mariadb/valkey: optimus-link (step 9) forwards the
# desktop's to the same ports, so both machines work against the same data.
# The formulae stay installed for their clients (psql, mariadb, valkey-cli).
# Tiling + focus-follows-mouse, like Hyprland. Needs Accessibility (see end).
yabai --start-service || true

# 6. Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "🐚 Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Change shell to zsh
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "🐚 Changing default shell to Zsh..."
    chsh -s "$(which zsh)"
fi

# 7. Claude Code CLI
if ! command -v claude &> /dev/null; then
    echo "🤖 Installing Claude Code CLI..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

# 8. GlassBar — full-width bar along the bottom of each screen, replacing
# the Dock visually, so the real Dock only slides up at the bottom edge
echo "🧊 Installing GlassBar..."
"$DOTFILES_DIR/mac/glassbar/install.sh"
defaults write com.apple.dock autohide -bool true
killall Dock

# 9. optimus-link — forwards the desktop's databases here, plus (while an ssh
# session to it is open) its other ports, this machine's adb, and copied images
echo "🔗 Installing optimus-link..."
"$DOTFILES_DIR/mac/optimus-link/install.sh"
brew services start syncthing
# Pops up a notification when Syncthing has to keep a conflict copy
"$DOTFILES_DIR/mac/sync-notify/install.sh"

# 10. Android SDK — the same platforms and build tools the desktop has, so the
# synced Android projects build here too
echo "🤖 Installing Android SDK..."
ANDROID_SDK="$HOME/Library/Android/sdk"
export JAVA_HOME="$(brew --prefix)/opt/openjdk"
yes | sdkmanager --sdk_root="$ANDROID_SDK" --licenses > /dev/null 2>&1 || true
sdkmanager --sdk_root="$ANDROID_SDK" "platform-tools" \
    "platforms;android-36" "platforms;android-37.0" "build-tools;36.0.0" "build-tools;37.0.0"

# 11. Wallpaper — mirrors whatever's active on the Linux box (quickshell
# itself doesn't run here; see mac/set-wallpaper.sh)
"$DOTFILES_DIR/mac/set-wallpaper.sh" || echo "🖼️  Skipped wallpaper (run mac/set-wallpaper.sh manually later)"

echo "✅ macOS setup complete!"
echo "   - Run 'pecl install redis' to add PHP Redis extension"
echo "   - Open Tailscale from Applications to connect to your network"
echo "   - Grant Accessibility to yabai (System Settings → Privacy & Security → Accessibility),"
echo "     then: yabai --restart-service"
