export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="jkrebs"
HYPHEN_INSENSITIVE="true"
COMPLETION_WAITING_DOTS="true"
HIST_STAMPS="yyyy-mm-dd"

plugins=(
		git
		web-search
		history-substring-search
	)

export EDITOR='nvim'

export PATH="$PATH:$HOME/.composer/vendor/bin"
export PATH="$HOME/.luaver/lua/5.1.5/bin:$PATH"
export PATH="$PATH:$HOME/.rvm/bin"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# opencode
export PATH=$HOME/.opencode/bin:$PATH

source $ZSH/oh-my-zsh.sh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

alias hyprland="uwsm start hyprland-uwsm.desktop"

export ODBCSYSINI=/opt/netsuite/odbcclient
export ODBCINI=/opt/netsuite/odbcclient/odbc64.ini
source /opt/netsuite/odbcclient/oaodbc64.sh
