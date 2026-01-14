{ config, pkgs, inputs, ... }:

let
  # Define your custom PHP with Redis enabled here, once.
  # We use 'pkgs.php' because we are outside the 'with pkgs' block below.
  myPhp = pkgs.php.withExtensions ({ enabled, all }: enabled ++ [ all.redis ]);
in
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
	fzf

    # --- Languages ---
    nodejs_22
    gcc
    gnumake
    python3
    go
    tree-sitter
    stdenv.cc.cc.lib
    zlib
    redis

    # --- Custom PHP & Composer ---
    myPhp
    myPhp.packages.composer

    # --- Desktop Tools ---
    waybar
    hyprpaper
    wofi
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

	inputs.opencode-flake.packages.${pkgs.system}.default
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
