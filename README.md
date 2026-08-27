# 🛠️ jkrebs Dotfiles

My personal dotfiles, optimized for a high-performance development environment on both **NixOS** and **Arch Linux**.

## 🚀 One-Shot Installation

Everything is automated. Get your base OS installed, connect to the internet, and run:

```bash
git clone git@github.com:jacobrk0528/dotfiles.git ~/dotfiles
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
4.  **Symlinks Configs**: Links Neovim, Hyprland, Quickshell, Tmux, Ghostty, and Zsh settings to your home directory.
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
*   **Claude Code**: Run `claude` and log in (auto-installed by `mac/setup.sh`; on Arch, install via `curl -fsSL https://claude.ai/install.sh | bash`).
*   **Slack/Chrome**: Manual login required.

---

## 🏹 Arch Linux Notes
*   Uses `paru` for AUR packages.
*   Enables Nvidia proprietary drivers and Pipewire audio.
*   MariaDB is initialized with a passwordless user '$USER'.
*   Redis is replaced by **Valkey** (Arch's default).

## 🔐 Login Screen (greetd)

Not enabled by default — login is still TTY + the `hyprland` alias until you turn it on.

```bash
quickshell/scripts/apply-theme          # generates quickshell-greeter/Colors.qml
sudo scripts/install-greeter.sh         # copies into /etc/greetd; enables nothing
sudo systemctl enable greetd.service    # takes effect on the next boot
```

`install-greeter.sh` copies the greeter rather than symlinking it: the `greeter`
user cannot read `/home`, so the QML, the palette and the wallpaper all have to
live under `/etc/greetd`. Re-run it after any change to the greeter or the theme.

**Rollback**, if the greeter fails to come up. Switch to a free VT with
Ctrl-Alt-F2, log in, and:

```bash
sudo systemctl disable --now greetd.service
sudo systemctl start getty@tty1.service   # back to the TTY login
```

Ctrl-Alt-F2 always works: `greetd.service` declares `Conflicts=getty@tty1`, so
enabling it stops the tty1 console — but logind still spawns a getty on any
other VT on demand. Nothing needs to be disabled by hand. greetd also gives up
after five failed restarts rather than looping, so a broken greeter leaves the
machine sitting idle, not thrashing.

If the greeter starts but cannot authenticate, `journalctl -b -u greetd` has the
PAM side of the conversation.

## 📂 Structure
*   `hypr/`: Hyprland configuration. `hyprland.lua` is the live config — there is no
    `hyprland.conf`; Hyprland loads the Lua directly. Also holds `hypridle`/`hyprlock`
    config, the generated colour files, and the wallpaper library.
*   `greetd/`: Login manager config and the throwaway compositor the greeter runs in.
*   `quickshell-greeter/`: The greeter itself. Self-contained — do not import from `quickshell/`.
*   `nvim/`: Custom Neovim setup (LazyVim based).
*   `quickshell/`: Desktop shell — status bar, notifications, launcher, control center,
    desktop widgets, and the wallpaper renderer. See `quickshell/README.md`.
*   `ghostty/`: Ghostty terminal configuration.
*   `yazi/`: Yazi file manager — keymap, theme, and options.
*   `dolphin/`: Dolphin/Qt settings, applied by `scripts/apply-dolphin.sh`.
*   `tmux/`: Per-project session scripts, `sessions.list`, and the session-jump bindings
    generated from it. Linked to `~/.tmux`.
*   `scripts/`: Shared setup and helper scripts — symlinking, greeter install, tmux session
    startup, NetSuite query export.
*   `zshrc`: Shell configuration and aliases.
*   `arch/`: Arch-specific package lists and setup scripts.
*   `nixos/`: NixOS configuration modules and flakes.
*   `mimeapps.list`: Default application associations.
*   `gitconfig`: Global Git configuration.
