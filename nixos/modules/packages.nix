{ config, pkgs, inputs, ... }:

let
  myPhp = pkgs.php.withExtensions ({ enabled, all }: enabled ++ [
    all.redis
    all.sqlite3
    all.pdo_odbc
  ]);
in
{
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    # --- Core ---
    vim
    neovim
    wget
    git
    zip
    unzip
    less
    rsync
    lsof
    usbutils
    unixODBC
    freetds
    psmisc

    # --- Shell / Terminal ---
    tmux
    ghostty
    fzf
    ripgrep
    jq
    htop
    cloc
    cmake
    tree
    wev
    bind           # dig, nslookup
    nmap
    whois
    netcat-gnu
    openbsd-netcat

    # --- Wayland / Hyprland ---
    grim
    slurp
    hypridle
    hyprshot
    hyprlock
    cliphist
    wl-clipboard
    wl-clip-persist
    uwsm
    quickshell
    greetd

    # --- Audio ---
    pavucontrol

    # --- Bluetooth ---
    blueman

    # --- File Manager ---
    # (thunar handled in desktop.nix)

    # --- Languages ---
    nodejs_22
    gcc
    gnumake
    python3
    go
    tree-sitter
    stdenv.cc.cc.lib
    zlib
    bun
    biome
    flutter
    cmake

    # --- Custom PHP & Composer ---
    myPhp
    myPhp.packages.composer

    # --- Databases ---
    pgadmin4-desktopmode

    # --- Apps ---
    google-chrome
    firefox
    chromium
    zen-browser
    slack
    postman
    obsidian
    obs-studio
    gimp
    kolourpaint
    remmina
    freerdp
    xrdp
    android-studio
    bibata-cursors
    google-cloud-sdk

    # --- OpenCode ---
    inputs.opencode-flake.packages.${pkgs.system}.default

    # NOTE: msodbcsql / mssql-tools not available in nixpkgs (proprietary).
    # Install manually via Microsoft's repo or use freetds as an alternative.
    # NOTE: tradingview not available in nixpkgs. Install via AppImage/AUR equivalent.
  ];

  environment.variables = {
    XCURSOR_THEME = "Bibata-Modern-Ice";
    XCURSOR_SIZE = "24";
    ANDROID_HOME = "$HOME/Android/Sdk";
  };

  fonts.packages = with pkgs; [
    font-awesome
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    noto-fonts-cjk-sans
  ];
}
