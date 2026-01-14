export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="jkrebs"
HYPHEN_INSENSITIVE="true"
COMPLETION_WAITING_DOTS="true"
HIST_STAMPS="yyyy-mm-dd"

plugins=(
		git
		zsh-autosuggestions
		zsh-syntax-highlighting
		web-search
		history-substring-search
	)

export EDITOR='nvim'

export PATH="$PATH:$HOME/.composer/vendor/bin"
export PATH="$HOME/.luaver/lua/5.1.5/bin:$PATH"
export PATH="/opt/homebrew/opt/php@8.2/bin:$PATH"
export PATH="$PATH:$HOME/.rvm/bin"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

if [ -f '/Users/jkrebs/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/jkrebs/google-cloud-sdk/path.zsh.inc'; fi
if [ -f '/Users/jkrebs/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/jkrebs/google-cloud-sdk/completion.zsh.inc'; fi

source ~/.config/oh-my-zsh/aliases.zsh
source /opt/netsuite/odbcclient/oaodbc64.sh

# opencode
export PATH=/home/jacob/.opencode/bin:$PATH
