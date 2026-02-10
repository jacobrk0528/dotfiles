# 🛠️ jkrebs Dotfiles

My personal dotfiles, optimized for a high-performance development environment on both **NixOS** and **Arch Linux**.

## 🚀 One-Shot Installation

Everything is automated. Get your base OS installed, connect to the internet, and run:

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

### What this does:
1.  **Detects OS**: Automatically switches between NixOS and Arch logic.
2.  **Creates Workspaces**: Sets up `~/Documents/TrinityRoad`, `~/Documents/Personal`, etc.
3.  **System Setup**:
    *   **NixOS**: Links `/etc/nixos` to this repo and runs `nixos-rebuild switch`.
    *   **Arch**: Enables `multilib`, installs `paru`, installs all packages, and configures MariaDB/Redis.
4.  **Symlinks Configs**: Links Neovim, Hyprland, Waybar, Tmux, and Zsh settings to your home directory.
5.  **Dev Stack**: Configures PHP, Redis, and MariaDB (creates user `jacob` on Arch).

---

## ❄️ NixOS Notes
*   Uses Nix Flakes.
*   Configuration is managed in the `nixos/` directory.
*   Hardware configuration is automatically backed up to the repo during install.

## 🏹 Arch Linux Notes
*   Uses `paru` for AUR packages.
*   Enables Nvidia proprietary drivers and Pipewire audio.
*   MariaDB is initialized with a passwordless user `jacob`.

## 📂 Structure
*   `hypr/`: Hyprland & Hyprpaper configuration.
*   `nvim/`: Custom Neovim setup (LazyVim based).
*   `waybar/`: Status bar configuration.
*   `zshrc`: Shell configuration and aliases.
*   `arch/`: Arch-specific package lists and setup scripts.
*   `nixos/`: NixOS configuration modules and flakes.
