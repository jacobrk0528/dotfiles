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
    *   **Arch**: Enables `multilib`, installs `paru`, installs all packages, and configures MariaDB/Valkey.
4.  **Symlinks Configs**: Links Neovim, Hyprland, Waybar, Tmux, Ghostty, and Zsh settings to your home directory.
5.  **Dev Stack**: Configures PHP, Valkey, and MariaDB (creates user '$USER' on Arch).

---

## 🛠️ New PC Migration Checklist

Since some parts of a system cannot (or should not) be automated, follow this checklist after running `./install.sh`:

### 1. OS-Level Configuration (Manual)
*   **NVIDIA & Wayland**: Ensure `nvidia-drm.modeset=1` is in your GRUB or systemd-boot kernel parameters.
*   **Kernel Hooks**: If using NVIDIA, you may need to add `nvidia nvidia_modeset nvidia_uvm nvidia_drm` to the `MODULES` array in `/etc/mkinitcpio.conf` and run `sudo mkinitcpio -P`.

### 2. Secrets & Identity
*   **SSH Keys**: Copy `~/.ssh/id_ed25519` (or generate new ones) and add to GitHub/GitLab.
*   **Git Config**: Your name/email are synced, but you'll need to re-authenticate with any remote providers.
*   **Gcloud**: Run `gcloud auth login` to re-authenticate.

### 3. Drivers & External Tools
*   **NetSuite ODBC**: Manually copy or install the drivers into `/opt/netsuite/odbcclient`.
*   **Netsuite Password**: Verify the `netsuite` alias in `oh-my-zsh/aliases.zsh`.
*   **Tailscale**: If you use tailscale IPs (e.g., for 'desktop'), install it with `sudo pacman -S tailscale` and run `sudo tailscale up`.

### 4. Application Auth
*   **Supermaven**: Re-authenticate in Neovim/Terminal.
*   **Opencode**: Ensure your token is valid or re-login.
*   **Slack/Chrome**: Manual login required.

---

## 🏹 Arch Linux Notes
*   Uses `paru` for AUR packages.
*   Enables Nvidia proprietary drivers and Pipewire audio.
*   MariaDB is initialized with a passwordless user '$USER'.
*   Redis is replaced by **Valkey** (Arch's default).

## 📂 Structure
*   `hypr/`: Hyprland & Hyprpaper configuration.
*   `nvim/`: Custom Neovim setup (LazyVim based).
*   `waybar/`: Status bar configuration.
*   `ghostty/`: Ghostty terminal configuration.
*   `zshrc`: Shell configuration and aliases.
*   `arch/`: Arch-specific package lists and setup scripts.
*   `nixos/`: NixOS configuration modules and flakes.
*   `mimeapps.list`: Default application associations.
*   `gitconfig`: Global Git configuration.
