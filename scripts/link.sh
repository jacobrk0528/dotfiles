#!/usr/bin/env bash

DOTFILES=$HOME/dotfiles

echo "🔗 Linking configuration files..."

# Usage: link_file "source_inside_dotfiles" "destination_path"
link_file() {
    src="$DOTFILES/$1"
    dest="$2"
    
    # Create the parent directory if it doesn't exist
    mkdir -p "$(dirname "$dest")"
    
    # Check if a real file/folder exists there (not a link) and back it up
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        echo "Backing up existing: $dest -> $dest.backup"
        mv "$dest" "$dest.backup"
    fi

    # Create the symbolic link (force overwrite if it exists)
    ln -sfn "$src" "$dest"
    echo "Linked $1 -> $dest"
}

# --- The Link List ---

link_file "hypr"        "$HOME/.config/hypr"
link_file "nvim"        "$HOME/.config/nvim"
link_file "waybar"      "$HOME/.config/waybar"

link_file "tmux"        "$HOME/.tmux"
link_file "tmux.conf"   "$HOME/.tmux.conf"
link_file "zshrc"       "$HOME/.zshrc"

link_file "oh-my-zsh/aliases.zsh"        "$HOME/.oh-my-zsh/custom/aliases.zsh"
link_file "oh-my-zsh/jkrebs.zsh-theme"   "$HOME/.oh-my-zsh/custom/themes/jkrebs.zsh-theme"

echo "Dotfiles linking complete!"
