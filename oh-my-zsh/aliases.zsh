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
