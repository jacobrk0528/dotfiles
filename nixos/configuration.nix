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
    extraGroups = [ "wheel" "networkmanager" "video" ];
    shell = pkgs.zsh;
    # User specific packages (kept separate from system packages)
    packages = with pkgs; [
      tree
    ];
  };

  # --- Services ---
  services.openssh.enable = true;
services.mysql = {
enable = true;
package = pkgs.mariadb;
};

services.redis.servers."" = {
enable= true;
port = 6379;
};

  # --- System State ---
  system.stateVersion = "25.11";
}
