# Flush the OS DNS cache. Only touches a cache that actually exists:
# macOS always has one; on Linux only systemd-resolved / nscd count.
# (Tailscale's 100.100.100.100 stub forwards without caching, and
# browsers keep their own cache that nothing here can clear.)
flushdns() {
	if [[ "$(uname)" == "Darwin" ]]; then
		sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
	elif systemctl -q is-active systemd-resolved 2>/dev/null; then
		resolvectl flush-caches
	elif systemctl -q is-active nscd 2>/dev/null; then
		sudo nscd -i hosts
	else
		echo "flushdns: no local DNS cache running, nothing to flush"
	fi
}

# Full reload: relink dotfiles, regenerate the theme, restart the desktop shell,
# then re-exec zsh. Ordered deliberately -- symlinks first so everything below
# reads the current files, and `exec zsh` dead last because it replaces this
# process and nothing after it would ever run.
#
# Adapts to where it is run:
#   local desktop  everything, including the quickshell + hyprland restart
#   ssh -> desktop the same: the running session is discovered from
#                  $XDG_RUNTIME_DIR and driven remotely
#   ssh -> server  shell, tmux and dns only; there is no session to reload
#   macOS          everything except the hyprland/quickshell bits, which do
#                  not exist there (the theme pass still refreshes ghostty,
#                  yazi and nvim colours)
_reload_step() { print -P "%F{blue}::%f $*" }
_reload_skip() { print -P "%F{242}--%f $*" }
_reload_warn() { print -P "%F{red}!!%f $*" }

# Locate a hyprland session belonging to this user and export the two variables
# hyprctl and quickshell need to talk to it. Already-correct when run from
# inside the session; the discovery is what makes `reload` over ssh work.
#
# The signature directory outlives a crashed compositor, so a live .socket.sock
# is the test, not the directory's existence.
_reload_find_session() {
	local xdg=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} sig

	[[ -n "$HYPRLAND_INSTANCE_SIGNATURE" \
		&& -S "$xdg/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]] || {
		HYPRLAND_INSTANCE_SIGNATURE=""
		for sig in $xdg/hypr/*(N/); do
			[[ -S "$sig/.socket.sock" ]] || continue
			HYPRLAND_INSTANCE_SIGNATURE=${sig:t}
		done
	}

	# Wayland clients (quickshell) need the display socket too. Only guess when
	# we are not already inside a session that told us which one to use.
	if [[ -z "$WAYLAND_DISPLAY" ]]; then
		local sock
		# (N=) selects sockets only, which skips the wayland-N.lock files.
		for sock in $xdg/wayland-*(N=); do
			WAYLAND_DISPLAY=${sock:t}
		done
	fi

	[[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]]
}

reload() {
	local dots=~/dotfiles
	local is_mac=0 has_session=0
	[[ "$(uname)" == "Darwin" ]] && is_mac=1

	# Exported so the hyprctl/qs calls below inherit them, and scoped to this
	# function so an ssh shell does not keep a desktop's variables afterwards.
	local -x HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
	if (( ! is_mac )) && _reload_find_session; then
		has_session=1
	fi

	if [[ -d "$dots" ]]; then
		_reload_step "relinking dotfiles"
		"$dots/scripts/link.sh" >/dev/null || _reload_warn "link.sh failed"

		# Writes the generated colour files for ghostty, yazi, nvim, tmux,
		# hyprland and the greeter. Safe everywhere: it only shells out to
		# hyprctl/tmux when they exist.
		if [[ -x "$dots/quickshell/scripts/apply-theme" ]]; then
			_reload_step "applying theme"
			"$dots/quickshell/scripts/apply-theme"
		fi
	else
		_reload_skip "no ~/dotfiles here, skipping relink + theme"
	fi

	if (( has_session )) && command -v qs >/dev/null 2>&1; then
		_reload_step "restarting quickshell (${WAYLAND_DISPLAY})"
		qs kill >/dev/null 2>&1
		# Wait for the old instance to actually go away; launching over a
		# still-running one races on the wayland layer surfaces.
		local i
		for i in {1..15}; do
			qs list 2>/dev/null | grep -q 'Process ID' || break
			sleep 0.2
		done
		qs -d >/dev/null 2>&1
	elif (( is_mac )); then
		_reload_skip "macOS, no quickshell"
	else
		_reload_skip "no wayland session reachable, leaving quickshell alone"
	fi

	if (( has_session )) && command -v hyprctl >/dev/null 2>&1; then
		_reload_step "reloading hyprland"
		hyprctl reload >/dev/null || _reload_warn "hyprctl reload failed"
	fi

	# Every live tmux server, not just the default socket. list-sessions fails
	# on a stale socket file without spawning a server, so dead ones are skipped
	# rather than resurrected.
	if command -v tmux >/dev/null 2>&1 && [[ -f ~/.tmux.conf ]]; then
		local sock
		for sock in ${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/*(N=); do
			tmux -S "$sock" list-sessions >/dev/null 2>&1 || continue
			_reload_step "reloading tmux (${sock:t})"
			tmux -S "$sock" source-file ~/.tmux.conf
		done
	fi

	_reload_step "flushing dns"
	flushdns

	# exec unconditionally. A missing ~/.zshrc is normal on a bare server, and
	# `source ~/.zshrc && exec zsh` would silently leave you in the old shell.
	_reload_step "re-execing zsh"
	[[ -f ~/.zshrc ]] && source ~/.zshrc
	exec zsh
}

alias rebuild="sudo nixos-rebuild switch --flake /etc/nixos"

# change to root
alias ~="cd ~"

# clear
alias c='clear'

# edit this file
alias editzsh='sudo vim ~/dotfiles/zshrc'
alias editzsha='nvim ~/dotfiles/oh-my-zsh/aliases.zsh'
alias edithypr='nvim ~/dotfiles/hypr/hyprland.lua'
alias editsys='sudo vim ~/dotfiles/nixos/'
alias editdotfiles='nvim ~/dotfiles'

# copy pwd
if [[ "$(uname)" == "Darwin" ]]; then
    alias cpwd='print -nr -- $PWD | pbcopy'
else
    alias cpwd='print -nr -- $PWD | wl-copy'
	copy() {
		if [ $# -eq 0 ]; then
			echo "Filename required"
		else
			cat "$1" | wl-copy
		fi
		return 0
	}
fi

# computer power options
# NB: deliberately not aliased to `shutdown` -- shadowing the real command
# with a no-confirm immediate variant means typing `shutdown` to read its
# usage powers the machine off instead.
alias byebye='systemctl poweroff'

# history
alias h='history'
alias clear_history='echo "" > ~/.zsh_history & exec $SHELL -l'

# Folder Alias
alias docs="cd ~/Documents"
alias downloads="cd ~/Downloads"
alias tr="cd ~/Documents/TrinityRoad/local-git"
alias personal="cd ~/Documents/Personal/"
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

# Recreate every autostart session from ~/.tmux/sessions.list, detached, exactly
# as login does. Safe to run any time: sessions that already exist are skipped.
alias start-tmux-sessions="~/dotfiles/scripts/start_tmux_sessions.sh"

# yazi, leaving the shell in whatever directory you navigated to on quit
y() {
	local tmp cwd
	tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd" || builtin true
	command rm -f -- "$tmp"
}

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

commit() {
    if [ $# -eq 0 ]; then
      echo "Commit Message required"
      return
    else
      git add .
      git commit -m "$1"
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

pr() {
    if [ $# -eq 0 ]; then
      echo "Title required"
      return
    else
      local body_file
      body_file=$(mktemp)
      nvim "$body_file"
      if [ ! -s "$body_file" ]; then
        echo "Empty body, aborting"
        rm -f "$body_file"
        return
      fi
      gh pr create --base main --head staging --title "$1" --body "$(cat "$body_file")"
      rm -f "$body_file"
    fi
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

alias netsuite='/home/jkrebs/dotfiles/scripts/ns_export/run.sh'
alias netsuiteRaw='isql Netsuite $NS_USER "$NS_PASSWORD"'

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
