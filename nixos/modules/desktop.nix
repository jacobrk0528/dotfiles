{ config, pkgs, ... }:

{
  programs.hyprland.enable = true;
  
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
