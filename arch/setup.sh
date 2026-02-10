#!/usr/bin/env bash

set -e

echo "🚀 Starting Arch Linux Setup..."

# 1. Enable Multilib
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "📦 Enabling multilib repository..."
    sudo sed -i '/^#\[multilib\]/,/Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf
    sudo pacman -Sy
fi

# 2. Install base dependencies
echo "📦 Installing base development tools..."
sudo pacman -S --needed --noconfirm base-devel git

# 3. Install Paru (AUR Helper)
if ! command -v paru &> /dev/null; then
    echo "📦 Installing paru..."
    temp_dir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$temp_dir"
    cd "$temp_dir"
    makepkg -si --noconfirm
    cd -
    rm -rf "$temp_dir"
fi

# 4. Install Packages
echo "📦 Installing packages from packages.txt..."
paru -S --needed --noconfirm - < "$(dirname "$0")/packages.txt"

# 5. Enable Services
echo "⚙️ Enabling services..."
sudo systemctl enable --now bluetooth
sudo systemctl enable --now redis
sudo systemctl enable --now sshd
sudo systemctl enable --now NetworkManager

# 6. MariaDB Setup
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "🗄️ Initializing MariaDB..."
    sudo mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    sudo systemctl enable --now mariadb
    
    echo "👤 Setting up MariaDB user 'jacob'..."
    # Wait for service to be ready
    sleep 3
    sudo mariadb -e "CREATE USER IF NOT EXISTS 'jacob'@'localhost' IDENTIFIED BY ''; GRANT ALL PRIVILEGES ON *.* TO 'jacob'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"
else
    sudo systemctl enable --now mariadb
fi

# 7. Zsh & Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "🐚 Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Change shell to zsh
if [ "$SHELL" != "/usr/bin/zsh" ]; then
    echo "🐚 Changing default shell to Zsh..."
    sudo chsh -s /usr/bin/zsh "$USER"
fi

echo "✅ Arch Linux setup logic complete!"
