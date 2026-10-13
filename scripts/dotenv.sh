# Loads ~/dotfiles/.env into the environment. Source this (bash); do not execute it.
#
# Every dotfiles script that needs a secret or a per-machine setting pulls it
# from that one file, so swapping a key is a one-line edit in one place. The
# file is gitignored; .env.example lists the keys it is expected to hold.
#
# Values are taken LITERALLY -- the file is parsed, never `source`d. A password
# containing `$!` used to abort nsq.sh with "unbound variable" (or, worse, be
# silently rewritten by the shell) when the env file was sourced under `set -u`.
# One pair of surrounding quotes is stripped; nothing else is interpreted, which
# matches how systemd's EnvironmentFile= and artoo's loader read the same file.
# Variables already set in the environment win over the file.
DOTFILES_ENV="${DOTFILES_ENV:-$HOME/dotfiles/.env}"

_dotenv_load() {
  local line key val
  [ -f "$DOTFILES_ENV" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key=${BASH_REMATCH[2]}
    val=${BASH_REMATCH[3]}
    val=${val%"${val##*[![:space:]]}"}
    if [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]]; then
      val=${BASH_REMATCH[1]}
    fi
    [ -n "${!key+x}" ] || export "$key=$val"
  done < "$DOTFILES_ENV"
}
_dotenv_load
unset -f _dotenv_load
