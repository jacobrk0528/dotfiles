{ config, pkgs, ... }:

{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # XDG Desktop Portal (needed for screen sharing, file pickers, etc.)
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
  };

  # File Manager (Thunar) & Plugins
  programs.thunar.enable = true;
  programs.thunar.plugins = with pkgs.xfce; [
    thunar-archive-plugin
    thunar-volman
  ];

  # Services needed for file management (Mounting, Trash, Thumbnails)
  services.gvfs.enable = true;
  services.tumbler.enable = true;
}
