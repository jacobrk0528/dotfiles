#!/usr/bin/env bash

set -e

# Get the directory of this script
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DOTFILES_DIR"

echo "🖥️  Starting Dotfiles Installation..."

# 1. Shared: Create directories
./scripts/makedirs.sh

# 2. Detect OS and Run System Setup
if [[ "$(uname)" == "Darwin" ]]; then
    echo "🍎 macOS detected."
    ./mac/setup.sh
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    case $ID in
        arch)
            echo "🏹 Arch Linux detected."
            ./arch/setup.sh
            ;;
        nixos)
            echo "❄️  NixOS detected."
            ./scripts/nixos-setup.sh
            # Trigger rebuild
            echo "🔄 Rebuilding NixOS system..."
            sudo nixos-rebuild switch --flake /etc/nixos
            ;;
        *)
            echo "⚠️  Unsupported OS: $ID"
            echo "Skipping system-level setup..."
            ;;
    esac
else
    echo "⚠️  Unknown OS. Skipping system-level setup..."
fi

# 3. Shared: Link Dotfiles
./scripts/link.sh

echo "✨ Setup finished! Please restart your terminal or log out/in."
