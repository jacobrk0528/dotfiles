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
brew services start postgresql@17
brew services start mariadb
brew services start valkey

# 6. PostgreSQL Setup
if ! psql -U "$USER" -c '\q' &> /dev/null 2>&1; then
    echo "🐘 Setting up PostgreSQL user and database..."
    sleep 2
    createuser --superuser "$USER" 2>/dev/null || true
    createdb "$USER" 2>/dev/null || true
    createdb "tomBombadil_local" 2>/dev/null || true
    psql -d "tomBombadil_local" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true
fi

# 7. MariaDB Setup
if ! mariadb -u root -e '\q' &> /dev/null 2>&1; then
    echo "🗄️  Setting up MariaDB user '$USER'..."
    sleep 2
    sudo mariadb -e "CREATE USER IF NOT EXISTS '$USER'@'localhost' IDENTIFIED BY ''; GRANT ALL PRIVILEGES ON *.* TO '$USER'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"
fi

# 8. Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "🐚 Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Change shell to zsh
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "🐚 Changing default shell to Zsh..."
    chsh -s "$(which zsh)"
fi

# 9. Claude Code CLI
if ! command -v claude &> /dev/null; then
    echo "🤖 Installing Claude Code CLI..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

# 10. Wallpaper — mirrors whatever's active on the Linux box (quickshell
# itself doesn't run here; see mac/set-wallpaper.sh)
"$DOTFILES_DIR/mac/set-wallpaper.sh" || echo "🖼️  Skipped wallpaper (run mac/set-wallpaper.sh manually later)"

echo "✅ macOS setup complete!"
echo "   - Run 'pecl install redis' to add PHP Redis extension"
echo "   - Open Tailscale from Applications to connect to your network"
