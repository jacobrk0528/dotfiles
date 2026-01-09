{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    
    ohMyZsh = {
      enable = true;
      theme = "jkrebs";
      custom = "/home/jacob/.config/oh-my-zsh";
      plugins = [ "git" "tmux" ];
    };
  };
}
