{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    ohMyZsh = {
      enable = true;
      theme = "jkrebs";
      custom = "/home/jacob/.oh-my-zsh/custom";
      plugins = [ "git" "web-search" "history-substring-search" "z" ];
    };
  };
}
