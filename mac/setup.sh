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
brew bundle --file="$DOTFILES_DIR/mac/Brewfile"

# 4. Enable Services
echo "⚙️  Starting services..."
brew services start postgresql@17
brew services start mariadb
brew services start valkey

# 5. PostgreSQL Setup
if ! psql -U "$USER" -c '\q' &> /dev/null 2>&1; then
    echo "🐘 Setting up PostgreSQL user and database..."
    sleep 2
    createuser --superuser "$USER" 2>/dev/null || true
    createdb "$USER" 2>/dev/null || true
    createdb "tomBombadil_local" 2>/dev/null || true
    psql -d "tomBombadil_local" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true
fi

# 6. MariaDB Setup
if ! mariadb -u root -e '\q' &> /dev/null 2>&1; then
    echo "🗄️  Setting up MariaDB user '$USER'..."
    sleep 2
    sudo mariadb -e "CREATE USER IF NOT EXISTS '$USER'@'localhost' IDENTIFIED BY ''; GRANT ALL PRIVILEGES ON *.* TO '$USER'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"
fi

# 7. Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "🐚 Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Change shell to zsh
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "🐚 Changing default shell to Zsh..."
    chsh -s "$(which zsh)"
fi

# 8. Claude Code CLI
if ! command -v claude &> /dev/null; then
    echo "🤖 Installing Claude Code CLI..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

# 9. Android SDK
if [ ! -d "$HOME/Library/Android/sdk" ]; then
    echo "📱 Android SDK not found. Open Android Studio to complete SDK setup."
fi

echo "✅ macOS setup complete!"
echo "   - Run 'pecl install redis' to add PHP Redis extension"
echo "   - Open Tailscale from Applications to connect to your network"
echo "   - Open Android Studio to finish Flutter/Android SDK setup"
