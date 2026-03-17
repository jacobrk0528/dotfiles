#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="$DOTFILES_DIR/mac/Brewfile"

echo "🍎  Starting macOS setup..."

ensure_command_line_tools() {
    if ! xcode-select -p >/dev/null 2>&1; then
        echo "🛠️  Installing Command Line Tools..."
        xcode-select --install || true
        echo "⚠️  Command Line Tools installation must finish before rerunning install.sh."
        exit 1
    fi
}

bootstrap_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "🍺  Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

brew_bundle() {
    echo "📦  Ensuring Homebrew packages are installed..."
    brew update
    brew bundle --file="$BREWFILE"
    brew cleanup --prune=all >/dev/null 2>&1 || true
}

install_oh_my_zsh() {
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo "🐚  Installing Oh My Zsh..."
        RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    if [ "$SHELL" != "/bin/zsh" ]; then
        echo "🐚  Setting default shell to zsh..."
        chsh -s /bin/zsh "$USER"
    fi
}

configure_mariadb() {
    if ! brew list --formula mariadb >/dev/null 2>&1; then
        return
    fi

    local brew_prefix
    brew_prefix="$(brew --prefix)"
    local mariadb_prefix
    mariadb_prefix="$(brew --prefix mariadb)"
    local datadir="$brew_prefix/var/mysql"

    if [ ! -d "$datadir/mysql" ]; then
        echo "🗄️  Initializing MariaDB data directory..."
        mkdir -p "$datadir"
        "$mariadb_prefix/bin/mariadb-install-db" --basedir="$mariadb_prefix" --datadir="$datadir" --user="$USER" >/dev/null
    fi

    echo "⚙️  Starting MariaDB via brew services..."
    brew services start mariadb >/dev/null 2>&1 || true
    sleep 3

    "$mariadb_prefix/bin/mariadb" -u root <<SQL || true
CREATE USER IF NOT EXISTS '$USER'@'localhost' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON *.* TO '$USER'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
}

configure_postgres() {
    local formula="postgresql@16"
    if ! brew list --formula "$formula" >/dev/null 2>&1; then
        return
    fi

    local brew_prefix
    brew_prefix="$(brew --prefix)"
    local pg_prefix
    pg_prefix="$(brew --prefix "$formula")"
    local data_dir="$brew_prefix/var/postgresql@16"

    if [ ! -f "$data_dir/PG_VERSION" ]; then
        echo "🐘  Initializing PostgreSQL cluster..."
        mkdir -p "$data_dir"
        "$pg_prefix/bin/initdb" -D "$data_dir" >/dev/null
        sed -i '' 's/peer/trust/g' "$data_dir/pg_hba.conf" || true
        sed -i '' 's/scram-sha-256/trust/g' "$data_dir/pg_hba.conf" || true
    fi

    echo "⚙️  Starting PostgreSQL via brew services..."
    brew services start "$formula" >/dev/null 2>&1 || true
    sleep 3

    "$pg_prefix/bin/createuser" -s "$USER" >/dev/null 2>&1 || true
    "$pg_prefix/bin/createdb" "tomBombadil_local" >/dev/null 2>&1 || true
    "$pg_prefix/bin/psql" -d "tomBombadil_local" -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null 2>&1 || true
}

configure_valkey() {
    if brew list --formula valkey >/dev/null 2>&1; then
        echo "⚙️  Starting Valkey via brew services..."
        brew services start valkey >/dev/null 2>&1 || true
    fi
}

ensure_command_line_tools
bootstrap_homebrew
brew_bundle
install_oh_my_zsh
configure_mariadb
configure_postgres
configure_valkey

echo "✅  macOS setup logic complete!"
