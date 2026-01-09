{ config, pkgs, ... }:

{
  # Allow unfree packages (Chrome, Nvidia, Slack, etc)
  nixpkgs.config.allowUnfree = true;
nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    # --- Core ---
    vim
    neovim
    wget
    git
    unzip
    unixODBC
    psmisc
slurp
grim
pavucontrol
wl-clipboard
ripgrep

    # --- Languages ---
    nodejs_22
    gcc
    gnumake
    python3
    go
    tree-sitter
	stdenv.cc.cc.lib
	zlib
php84Packages.composer

    # --- Desktop Tools ---
    waybar
    wofi
    pavucontrol
    blueman
    ghostty
    tmux

    # --- Apps ---
    google-chrome
    slack
    postman
    remmina
    xrdp

    bibata-cursors
  ];

  environment.variables = {
  XCURSOR_THEME = "Bibata-Modern-Ice";
  XCURSOR_SIZE = "24";
  };

  fonts.packages = with pkgs; [
    font-awesome
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
  ];
}
