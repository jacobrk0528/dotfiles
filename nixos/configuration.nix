# /etc/nixos/configuration.nix
{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/nvidia.nix
    ./modules/desktop.nix
    ./modules/sound.nix
    ./modules/shell.nix
    ./modules/packages.nix
  ];

  # --- Bootloader ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [ "usbcore.autosuspend=-1" ];

  # --- Hardware ---
  hardware.enableAllFirmware = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = false;
      };
    };
  };

  # --- Networking ---
  networking.hostName = "jkrebs-desktop";
  networking.networkmanager.enable = true;

  # --- Time & Locale ---
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # --- User Configuration ---
  users.users.jacob = {
    isNormalUser = true;
    description = "Jacob Krebs";
    extraGroups = [ "wheel" "networkmanager" "video" "adbusers" ];
    shell = pkgs.zsh;
  };

  # --- Services ---
  services.openssh.enable = true;
  services.tailscale.enable = true;

  # Android debugging
  programs.adb.enable = true;

  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
  };

  services.valkey.servers."" = {
    enable = true;
    port = 6379;
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17.withPackages (ps: [ ps.pgvector ]);

    ensureDatabases = [ "tomBombadil_local" ];

    ensureUsers = [
      {
        name = "jacob";
        ensureClauses.superuser = true;
      }
    ];

    authentication = pkgs.lib.mkForce ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   all             all                                     trust
      host    all             all             127.0.0.1/32            trust
      host    all             all             ::1/128                 trust
    '';
  };

  # --- System State ---
  system.stateVersion = "25.11";
}
