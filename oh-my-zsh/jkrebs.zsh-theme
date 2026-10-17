# ~/.oh-my-zsh/custom/themes/jkrebs.zsh-theme
local GRAY="%F{245}"
local RED="%F{9}"     # soft pink (closer to #EB6F92)
local YELLOW="%F{180}"     # soft beige/yellow (like #F6C177)
local FOAM="%F{110}"     # desaturated teal (like #9CCFD8)
local GREEN="%F{114}"    # clean green (like #31748F)
local RESET="%f"
# Git info (green if clean, rose w/ ✗ if dirty)
git_branch_info() {
  local branch dirty
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return
  dirty=$(git status --porcelain 2>/dev/null)
  if [[ -n "$dirty" ]]; then
    echo " ${RED}($branch)${RESET}"
  else
    echo " ${GREEN}($branch)${RESET}"
  fi
}
# Set git_branch_info as a precmd function
autoload -Uz add-zsh-hook
add-zsh-hook precmd git_prompt_update
# Function to update git prompt info
git_prompt_update() {
  GIT_INFO=$(git_branch_info)
}
# Banner above the prompt while Syncthing is still pulling the other machine's
# changes into this folder (see scripts/sync-status). Silent when it is safe to
# edit, and never consulted outside the shared folders.
sync_prompt_update() {
  SYNC_INFO=""
  [[ "$PWD/" == "$HOME/Documents/"* || "$PWD/" == "$HOME/Downloads/"* ]] || return
  local msg
  msg=$(sync-status --prompt 2>/dev/null)
  [[ -n "$msg" ]] && SYNC_INFO="$msg"$'\n'
}
add-zsh-hook precmd sync_prompt_update
# Main prompt structure
PROMPT='${SYNC_INFO}${GRAY}[%n@%m:${YELLOW}%~${GRAY}/]${GIT_INFO}
${FOAM}%# ${RESET}'
