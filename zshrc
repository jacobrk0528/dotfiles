export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="jkrebs"
HYPHEN_INSENSITIVE="true"
COMPLETION_WAITING_DOTS="true"
HIST_STAMPS="yyyy-mm-dd"

plugins=(
		git
		web-search
		history-substring-search
		z
	)

export EDITOR='nvim'

export PATH="$PATH:$HOME/.composer/vendor/bin"
export PATH="$HOME/.luaver/lua/5.1.5/bin:$PATH"
export PATH="$PATH:$HOME/.rvm/bin"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# opencode
export PATH=$HOME/.opencode/bin:$PATH

source $ZSH/oh-my-zsh.sh

if [[ "$(uname)" == "Darwin" ]]; then
    BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
    source "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    source "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    export ANDROID_HOME="$HOME/Library/Android/sdk"
    export PATH="$PATH:/usr/local/opt/postgresql@17/bin"
else
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    export ANDROID_HOME="$HOME/Android/Sdk"
    alias hyprland="uwsm start hyprland-uwsm.desktop"
fi

export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

[ -f /opt/netsuite/odbcclient/oaodbc64.sh ] && {
    export ODBCSYSINI=/opt/netsuite/odbcclient
    export ODBCINI=/opt/netsuite/odbcclient/odbc64.ini
    source /opt/netsuite/odbcclient/oaodbc64.sh
}

export PATH="$HOME/.local/bin:$PATH"

[ -f ~/.local/share/attention/attention.zsh ] && source ~/.local/share/attention/attention.zsh

source <(fzf --zsh)
export PATH="$PATH:$HOME/.config/composer/vendor/bin"
export REPORTTIME=30

export PATH="$PATH:$HOME/dotfiles/hypr/scripts"
