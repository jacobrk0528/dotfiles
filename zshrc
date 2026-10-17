export ZSH="$HOME/.oh-my-zsh"

# Keep $PATH free of duplicates. Every PATH export below appends
# unconditionally, and `reload` re-sources this file into the same process,
# so without this the same entries stack up on every reload.
typeset -U path PATH

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

# opencode
export PATH=$HOME/.opencode/bin:$PATH

source $ZSH/oh-my-zsh.sh

if [[ "$(uname)" == "Darwin" ]]; then
    BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
    source "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    source "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    export ANDROID_HOME="$HOME/Library/Android/sdk"
    # Homebrew's JDK is keg-only, so gradle can't find it without this.
    export JAVA_HOME="$BREW_PREFIX/opt/openjdk"
    export PATH="$JAVA_HOME/bin:$PATH"
    export PATH="$PATH:/usr/local/opt/postgresql@17/bin"
    # The databases live on the desktop; optimus-link forwards them to
    # localhost. Point the clients at TCP instead of a local socket that no
    # longer has a server behind it.
    export PGHOST=localhost MYSQL_HOST=127.0.0.1
else
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    export ANDROID_HOME="$HOME/Android/Sdk"
    alias hyprland="uwsm start hyprland-uwsm.desktop"

    # Working from the laptop over ssh (see mac/optimus-link). While it is
    # connected, the laptop's adb server is tunnelled to :5038 here. Before each
    # prompt, switch adb/gradle/flutter over to it if a phone is plugged in
    # there, and back to this machine's own server otherwise. Asks the server
    # directly instead of running `adb devices`, which would spawn a stray
    # daemon on :5038 whenever the tunnel is down.
    zmodload zsh/net/tcp zsh/system
    _laptop_adb() {
        unset ANDROID_ADB_SERVER_PORT
        local fd chunk reply
        ztcp 127.0.0.1 5038 2>/dev/null || return 0
        fd=$REPLY
        print -n -u $fd '000chost:devices'
        while sysread -t 1 -i $fd chunk 2>/dev/null; do reply+=$chunk; done
        ztcp -c $fd
        [[ "$reply" == *$'\tdevice'* ]] && export ANDROID_ADB_SERVER_PORT=5038
        return 0
    }
    precmd_functions+=(_laptop_adb)

    # optimus-link also pushes images copied on the laptop into this desktop's
    # clipboard. An ssh shell has no WAYLAND_DISPLAY to read it with, so lend
    # Claude Code the running session's for that one process rather than
    # exporting a desktop's variables into the whole ssh shell.
    if [[ -n "$SSH_CONNECTION" && -z "$WAYLAND_DISPLAY" ]]; then
        claude() {
            local xdg=${XDG_RUNTIME_DIR:-/run/user/$UID} sock display
            # (N=) selects sockets only, which skips the wayland-N.lock files.
            for sock in $xdg/wayland-*(N=); do display=${sock:t}; done
            if [[ -n "$display" ]]; then
                XDG_RUNTIME_DIR=$xdg WAYLAND_DISPLAY=$display command claude "$@"
            else
                command claude "$@"
            fi
        }
    fi
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

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
