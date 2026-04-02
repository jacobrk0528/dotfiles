# Reload Shell
alias reload="source ~/.zshrc && exec zsh"
alias rebuild="sudo nixos-rebuild switch --flake /etc/nixos"

# change to root
alias ~="cd ~"

# clear
alias c='clear'

# edit this file
alias editzsh='sudo vim ~/dotfiles/zshrc'
alias editzsha='nvim ~/dotfiles/oh-my-zsh/aliases.zsh'
alias edithypr='nvim ~/dotfiles/hypr/hyprland.conf'
alias editsys='sudo vim ~/dotfiles/nixos/'
alias editdotfiles='nvim ~/dotfiles'

# copy pwd
alias cpwd='pwd|tr -d "\n"|pbcopy'

# computer power options
alias shutdown='shutdown now'

# history
alias h='history'
alias clear_history='echo "" > ~/.zsh_history & exec $SHELL -l'

# Folder Alias
alias docs="cd ~/Documents"
alias downloads="cd ~/Downloads"
alias tr="cd ~/Documents/TrinityRoad/local-git"
alias personal="cd ~/Documents/Personal/local-git"
alias scripts="cd ~/Documents/TrinityRoad/scripts"

# Python 3
alias python=python3

# mysql
alias mysql="mariadb -u root"

# NPM Run Dev
alias nrd="npm run dev"

# better ls
alias ll="ls -lah"

#git
alias gs="git status"

# tmux commands
alias tls="tmux ls"

tks() {
    if [ $# -eq 0 ]; then
        tmux kill-server
    else
        tmux kill-session -t "$1"
    fi
}

alias ta="~/.tmux/load_or_create.sh"

push() {
    if [ $# -eq 0 ]; then
      echo "Commit Message required"
      return
    else
      git add .
      git commit -m "$1"
      git push
    fi
}

alias pull="git pull"

gitcheck() {
  find . -type d -name .git -prune -execdir sh -c '
  if [ -n "$(git status --porcelain)" ]; then
    echo "DIRTY: $(pwd)"
  fi
' \;
}

#alias nvim="/home/jacob/.bash_scripts/nvim.sh"

create-shell() {
    if [ -f shell.nix ]; then
        echo "shell.nix already exists."
    else
        cat <<EOF > shell.nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Add packages here
    # hello
    # git
  ];

  shellHook = ''
    echo "Welcome to your development shell!"
  '';
}
EOF
        echo "Created shell.nix."
    fi
    nvim shell.nix
}

alias netsuite='isql Netsuite NS_USER_PLACEHOLDER "NS_PASSWORD_PLACEHOLDER"'

alias whichmodel='echo -e "\n\033[1;34mOpenCode Zen 2026 Model Guidance\033[0m"; \
printf "%-22s | %-12s | %-12s | %-30s\n" "Model Name" "In $/1M" "Out $/1M" "Best For..."; \
printf "%.100s\n" "----------------------------------------------------------------------------------------------------"; \
printf "%-22s | %-12s | %-12s | %-30s\n" "Trinity Large (Pre)" "FREE" "FREE" "Junior Dev / First Drafts"; \
printf "%-22s | %-12s | %-12s | %-30s\n" "Big Pickle (Stealth)" "FREE" "FREE" "Experimental Frontier Tasks"; \
printf "%-22s | %-12s | %-12s | %-30s\n" "MiniMax M2.5" "\$0.30" "\$1.20" "Daily Driver / Feature Build"; \
printf "%-22s | %-12s | %-12s | %-30s\n" "Gemini 3 Flash" "\$0.50" "\$3.00" "PROJECT MANAGER / Full Repo"; \
printf "%-22s | %-12s | %-12s | %-30s\n" "Kimi K2.5 (Thinking)" "\$0.60" "\$3.00" "Complex Debugging Logic"; \
printf "%-22s | %-12s | %-12s | %-30s\n" "GPT-5.3 Codex" "\$1.75" "\$14.00" "Precise Terminal/DevOps"; \
printf "%-22s | %-12s | %-12s | %-30s\n" "Gemini 3.1 Pro" "\$2.00" "\$12.00" "High-Context Engineering"; \
printf "%-22s | %-12s | %-12s | %-30s\n" "Claude 4.6 Opus" "\$5.00" "\$25.00" "The ARCHITECT / Hard Logic"; \
echo -e "\n\033[1;33mPRO TIP:\033[0m Start with Trinity/MiniMax. Use Gemini for planning. Escalate to Opus only when stuck.\n"'
