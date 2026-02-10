#!/usr/bin/env bash

DOTFILES=$HOME/dotfiles

echo "❄️  Setting up NixOS System Configuration..."

if [ -f /etc/nixos/hardware-configuration.nix ]; then
    echo "   ℹ️  Copying current hardware-configuration.nix to dotfiles..."
    cp /etc/nixos/hardware-configuration.nix "$DOTFILES/nixos/hardware-configuration.nix"
    git -C "$DOTFILES" add "$DOTFILES/nixos/hardware-configuration.nix"
fi

if [ ! -L /etc/nixos ]; then
    echo "   🗑️  Removing default /etc/nixos..."
    sudo rm -rf /etc/nixos
fi

echo "   🔗 Linking /etc/nixos -> $DOTFILES/nixos..."
sudo ln -sfn "$DOTFILES/nixos" /etc/nixos

echo "System linking complete! You can now run 'nixos-rebuild switch --flake .'"
