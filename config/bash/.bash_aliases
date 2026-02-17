# shellcheck shell=bash
# -------------------
# Colors & Styling
# -------------------

# ANSI Color Codes
_C_RESET=$'\033[0m'
_C_RED=$'\033[1;31m'
_C_GREEN=$'\033[1;32m'
_C_YELLOW=$'\033[1;33m'
_C_BLUE=$'\033[1;34m'
_C_MAGENTA=$'\033[1;35m'
_C_CYAN=$'\033[1;36m'
_C_BOLD=$'\033[1m'
_C_ULINE=$'\033[4m'
_C_CAT_RED=$'\033[38;2;243;139;168m' # Catppuccin Red
_C_DARK_GRAY=$'\033[38;5;237m' # xterm-256 Color 237

# -------------------
# General Purpose
# -------------------

# Safer file operations by prompting for confirmation.
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Use Neovim instead of Vim for a better editing experience.
if command -v nvim &>/dev/null; then
  alias vim='nvim'
fi

# Use micro as a modern replacement for nano
if command -v micro &>/dev/null; then
  alias nano='micro'
fi

# Use 'bat' (or 'batcat') for a 'cat' with syntax highlighting.
_BAT_CMD="cat"
if command -v bat &>/dev/null; then
  alias cat='bat'
  _BAT_CMD="bat"
elif command -v batcat &>/dev/null; then
  alias cat='batcat'
  _BAT_CMD="batcat"
fi

# Use 'less' as a pager for 'ag' search results.
alias ag="ag --pager='less -XFR'"

# Add color to the output of the 'ip' command.
alias ip='ip -c'

# Always use color and case-insensitive matching for 'grep'.
alias grep='grep --color=auto -i'

# Go up one directory.
alias ..='cd ..'

# -------------------
# Man Pages
# -------------------

# Configure colored man pages.
# Prefer 'bat' if available, otherwise use 'less' with termcap colors.
# Force 'man' to use legacy formatting (no ANSI SGR) so tools can process it.
export MANROFFOPT="-c"

if [[ "$_BAT_CMD" != "cat" ]]; then
  export MANPAGER="sh -c 'col -bx | $_BAT_CMD -l man -p'"
else
  unset MANPAGER
  export LESS_TERMCAP_mb=$'\E[1;31m'     # begin blinking
  export LESS_TERMCAP_md=$'\E[1;31m'     # begin bold
  export LESS_TERMCAP_me=$'\E[0m'        # end mode
  export LESS_TERMCAP_se=$'\E[0m'        # end standout-mode
  export LESS_TERMCAP_so=$'\E[1;44;33m'  # begin standout-mode - info box
  export LESS_TERMCAP_ue=$'\E[0m'        # end underline
  export LESS_TERMCAP_us=$'\E[1;32m'     # begin underline
fi

# -------------------
# FZF Configuration
# -------------------

# Shared styles and options for FZF functions.
# Includes layout, keybindings for preview toggling, and the default "Blue" color theme.
_FZF_LBL_STYLE=$'\033[38;2;255;255;255;48;2;45;63;118m'
_FZF_LBL_RESET="${_C_RESET}"

_FZF_COMMON_OPTS=(
  --ansi --reverse --tiebreak=index --header-first --border=top
  --preview-window 'right,60%,border,wrap'
  --border-label-pos='3'
  --preview-label-pos='3'
  --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)'
  --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff'
  --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7'
)

_FZF_CHEATSHEET_THEME=(
  --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030'
  --color 'fg:#c8d3f5,query:#c8d3f5:regular'
  --color 'border:#f9e2af,label:#f9e2af:reverse'
  --color 'header:#ff966c,separator:#ff966c'
  --color 'info:#545c7e,scrollbar:#589ed7'
  --color 'marker:#ff007c,pointer:#ff007c,spinner:#ff007c'
  --color 'prompt:#65bcff'
)

_FZF_CHEATSHEET_OPTS=(
  --ansi
  --border=rounded
  --border-label-pos='3'
  --layout=reverse
  --prompt='  Run❯ '
  --delimiter=":"
  "--with-nth=2.."
)

# --- FZF Environment & Bindings ---

# Determine if we should use 'fd' or 'fdfind'
_FD_CMD="fd"
if ! command -v fd &>/dev/null && command -v fdfind &>/dev/null; then
  _FD_CMD="fdfind"
fi

# Use fd as the default command for fzf to use for finding files.
export FZF_DEFAULT_COMMAND="$_FD_CMD --hidden --follow --exclude \".git\""

# Options for CTRL-T (insert file path in command line)
export FZF_CTRL_T_OPTS="--style full \
    --input-label ' Input ' --header-label ' File Type ' \
    --preview 'fzf-preview.sh {}' \
    --layout reverse \
    --bind 'result:transform-list-label: \
        if [[ -z \$FZF_QUERY ]]; then \
          echo \" \$FZF_MATCH_COUNT items \" \
        else \
          echo \" \$FZF_MATCH_COUNT matches for [\$FZF_QUERY] \" \
        fi \
        ' \
    --bind 'focus:transform-preview-label:[[ -n {} ]] && printf \" Previewing [%s] \" {}' \
    --bind 'focus:+transform-header:file --brief {} || echo \"No file selected\"' \
    --color 'border:#aaaaaa,label:#cccccc,preview-border:#9999cc,preview-label:#ccccff' \
    --color 'list-border:#669966,list-label:#99cc99,input-border:#996666,input-label:#ffcccc' \
    --color 'header-border:#6699cc,header-label:#99ccff'"

# Options for ALT-C (cd into a directory)
export FZF_ALT_C_OPTS="--exact --style full \
    --input-label ' Change Directory ' \
    --preview 'eza --tree --level=1 --color=always --icons --group-directories-first {}' \
    --layout reverse \
    --bind 'result:transform-list-label: \
        if [[ -z \$FZF_QUERY ]]; then \
          echo \" \$FZF_MATCH_COUNT items \" \
        else \
          echo \" \$FZF_MATCH_COUNT matches for [\$FZF_QUERY] \" \
        fi \
        ' \
    --bind 'focus:transform-preview-label:[[ -n {} ]] && printf \" Previewing [%s] \" {}' \
    --color 'border:#aaaaaa,label:#cccccc,preview-border:#9999cc,preview-label:#ccccff' \
    --color 'list-border:#669966,list-label:#99cc99,input-border:#996666,input-label:#ffcccc'"

# --- FZF Completion Overrides ---
# Use fd to power fzf's path and directory completion (**<TAB>).
_fzf_compgen_path() {
  $_FD_CMD --hidden --follow --exclude ".git" . "$1"
}
_fzf_compgen_dir() {
  $_FD_CMD --type d --hidden --follow --exclude ".git" . "$1"
}

# --- Custom FZF Functions ---
# Custom function to find a file and open it in Neovim.
alias fzf_nvim='dv-find.sh'
unset -f dv-find

# fif - Find in Files
# Purpose: Interactive search of file contents using ripgrep and fzf.
# Usage: fif [query]
alias fif='dv-fif.sh'
unset -f dv-fif


# fhistory - Fuzzy History
# Purpose: Interactively search and select commands from history.
# Usage: fhistory
fhistory() {
  local output
  local key
  local cmd

  # Pipe history into the standalone script.
  # We pass the current readline buffer as the initial query.
  # HISTTIMEFORMAT="" ensures no timestamps are passed to the script.
  output=$(HISTTIMEFORMAT="" history | dv-history.sh "$READLINE_LINE")
  
  # If the script exited with non-zero (cancelled), do nothing.
  [[ $? -ne 0 ]] && return

  # Parse output: Line 1 is Key, Line 2 is Command
  key=$(head -1 <<< "$output")
  cmd=$(tail -n +2 <<< "$output")

  if [[ -n "$cmd" ]]; then
    if [[ "$key" == "ctrl-e" ]]; then
      # Execute mode: Run the command immediately
      # Add to history so it appears as the most recent command
      history -s "$cmd"
      printf "❯ %s\n" "$cmd"
      eval "$cmd"
      # Clear the buffer
      READLINE_LINE=""
      READLINE_POINT=0
    else
      # Edit mode: Place command on the readline buffer
      READLINE_LINE="$cmd"
      READLINE_POINT=${#cmd}
    fi
  fi
}

# fman - Fuzzy Man Pages
# Purpose: Interactively search and open man pages.
# Usage: fman
alias fman='dv-man.sh'

unset -f dv-man

# -------------------
# Git
# -------------------

# Check the status of the git repository (short format).
alias gs='git status -sb'

# List all local and remote branches.
alias gb='git branch -a'

# Stage files for a commit.
alias ga='git add'

# Commit staged files with a message.
alias gc='git commit -m'

# Push commits to the remote repository.
alias gp='git push'

# Launch lazygit, a terminal UI for git.
alias lg='lazygit'

# --- Reusable Git Helper Variables & Functions ---

# Helper to ensure the current directory is a git repository.
_require_git_repo() {
  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    printf "%b✗ Error:%b Not a git repository\n" "${_C_CAT_RED}" "${_C_RESET}"
    return 1
  fi
}

# A compact and graphical view of commit history.
# Using a function for better readability and to handle arguments.
# We unalias 'gl' first to prevent conflicts with any pre-existing alias.
unalias gl 2>/dev/null
gl() {
  _require_git_repo || return 1
  git log --graph --color=always --pretty=format:'%C(yellow)%h%C(reset) %C(green)(%cr)%C(reset)%C(bold cyan)%d%C(reset) %s %C(blue)<%an>%C(reset)' "$@"
}

# See the commit history for a specific file, tracking renames.
# Usage: glf <file_path>
unalias glf 2>/dev/null
glf() {
  _require_git_repo || return 1
  git log --follow --color=always --pretty=format:'%C(yellow)%h%C(reset) %C(green)(%cr)%C(reset)%C(bold cyan)%d%C(reset) %s %C(blue)<%an>%C(reset)' -- "$@"
}

# Helper to handle the selection from fgl and fzglfh.
_handle_git_hash_selection() {
  local selected="$1"
  [[ -z "$selected" ]] && return

  # Strip ANSI codes and extract the first field (hash)
  local hash
  hash=$(echo "$selected" | sed $'s/\e\[[0-9;]*m//g' | awk '{print $1}')

  # Always add to history so it can be retrieved later
  history -s "$hash"

  if [[ -v READLINE_LINE ]]; then
    # If called via bind -x, append to the command line
    if [[ -n "$READLINE_LINE" && "$READLINE_LINE" != *" " ]]; then
      READLINE_LINE="${READLINE_LINE} "
    fi
    READLINE_LINE="${READLINE_LINE}${hash}"
    READLINE_POINT=${#READLINE_LINE}
  else
    # If called directly, print a message confirming the action
    printf "Added hash to history (Press Up-Arrow to use)\n %s" "$hash"
  fi
}

# -------------------
# Git with FZF
# -------------------

# fgl - Fuzzy Git Log
# Purpose: Interactively browse git commit history
# Usage: fgl [git log options]
fgl() {
  local selected
  # dv-git-log.sh will print the selected line to stdout when not in a tmux popup
  # The _require_git_repo check is inside the subshell to prevent error messages from polluting the output if it fails.
  selected=$(_require_git_repo && dv-git-log.sh "$@")
  _handle_git_hash_selection "$selected"
}

# fgb - Fuzzy Git Branch
# Purpose: Interactively checkout local or remote git branches
# Usage: fgb (Delegates to dv-git-branch)
alias fgb='_require_git_repo && dv-git-branch.sh'

# fzglfh - Fuzzy Git Log File History
# Purpose: Interactively browse commit history of a specific file
# Usage: fzglfh (Delegates to dv-git-history)
alias fzglfh='_require_git_repo && dv-git-history.sh'

# fgs - Fuzzy Git Stash
# Purpose: Interactively view, apply, and drop git stashes
# Usage: fgs (Delegates to dv-git-stash)
alias fgs='_require_git_repo && dv-git-stash.sh'

# -------------------
# System, Network & Packages
# -------------------

# update
# Purpose: Update system packages and check if a reboot is required
# Usage: update
unalias update 2>/dev/null
alias update='dv-update.sh'
unset -f dv-update

# check-reboot
# Purpose: Check if the system requires a reboot (Debian/Ubuntu specific).
# Usage: check-reboot
unalias check-reboot 2>/dev/null
check-reboot() {
  local color="${_C_GREEN}"
  local msg="✓ No Reboot Required"

  if [ -f /var/run/reboot-required ]; then
    color="${_C_RED}"
    msg=" Reboot Required"
  fi
  printf "%s%s%s\n" "${color}" "${msg}" "${_C_RESET}"
}

# Get public IP address from ipinfo.io.
alias myip='curl -s ipinfo.io/ip'

# ports
# Purpose: List listening TCP/UDP ports with process info in a table
# Usage: ports
unalias ports 2>/dev/null
alias ports='dv-ports.sh'
unset -f dv-ports

# List all running processes with essential columns.
alias psa='ps -eo user,pid,pcpu,pmem,command'

# -------------------
# Process Management
# -------------------

# fzfkill
# Purpose: Interactively find and kill processes
# Usage: fzfkill
alias fzfkill='dv-kill.sh'
unset -f fzfkill
unset -f dv-kill

# -------------------
# File & Directory Listing (using eza)
# -------------------
# NOTE: These aliases require 'eza', a modern 'ls' replacement, to be
#       installed.

if command -v eza &>/dev/null; then
  # --- Core Replacements ---
  # Default 'ls' replacement, grouping directories first.
  alias ls='eza --group-directories-first'

  # Simple listing with file type indicators.
  # -F: Appends indicators (e.g., / for dirs, * for execs).
  alias l='ls -F'

  # Long format listing
  # -l: Long listing format (permissions, size, user, date)
  # -b: Binary file sizes (k, M, G) instead of bytes
  # -G: Grid view (columns) even in long format (saves vertical space)
  # --icons: Show icons
  # --smart-group: Only show group if different from user
  # Note: Add --no-time to hide the date column
  alias ll='eza -lbG --icons --smart-group --group-directories-first'

  # --- Tree Views ---
  # Use eza as a modern replacement for tree
  # --tree: Tree view
  # --icons: Show icons
  alias tree='eza --tree --icons --group-directories-first'

  # Tree view of the current directory, one level deep.
  # --level=1: Limit tree depth to 1 level.
  # -h: Show header row.
  # -a: All files (including hidden).
  # -l: Long listing format.
  # --smart-group: Only show group if different from user.
  # --no-time: Hide the date column.
  alias lt='tree --level=1 -hal --smart-group --no-time'

  # --- Specialized Views ---
  # List only directories
  # -D: List only directories
  # -h: Show header row
  # -a: All files (including hidden)
  # --no-filesize: Hides size column (dirs usually 4kb, not useful)
  # --smart-group: Only show group if different from user
  # --no-time to hide the date column
  alias ld='eza -Dhal --no-filesize --smart-group --icons --no-time'

  # Detailed listing, sorted by size, with Git status (using eza).
  # -a: All files (including hidden).
  # -l: Long format.
  # --git: Show git status column.
  # --sort=size: Sort by file size.
  alias la='eza -al --git --smart-group --icons --sort=size --group-directories-first'
fi

# -------------------
# Session Management
# -------------------

# tmux
# Purpose: Connect to a session named 'main', creating it if it doesn't exist
#          -A: Attach to existing session.
tmux_launch() {
  command tmux new-session -A -s main
}
alias t='tmux_launch'

# -------------------
# Custom Utilities
# -------------------
alias dsh='dv-dsh.sh'
alias path='dv-path.sh'
alias sshm='dv-ssh-manager.sh'

# -------------------
# Interactive Tools & Keybindings
# -------------------

# show_alias_cheatsheet
# Purpose: Display a cheatsheet of aliases and functions defined in this file
# Usage: Bound to Alt+x ?
show_alias_cheatsheet() {
  # Define base options
  local fzf_opts=("${_FZF_CHEATSHEET_OPTS[@]}" --border-label=' Alias Cheatsheet ')
  
  # Add tmux popup options if in tmux, otherwise fallback to height
  if [[ -n "$TMUX" ]]; then
    fzf_opts+=(--tmux "center,60%,60%")
  else
    fzf_opts+=(--height='80%')
  fi

  # Define the list of aliases
  # Alias : Description (Command)
  local selected
  selected=$(cat <<EOF | fzf "${fzf_opts[@]}" "${_FZF_CHEATSHEET_THEME[@]}"
.. :${_C_YELLOW}..${_C_RESET}       : Go up one directory (cd ..)
cat :${_C_YELLOW}cat${_C_RESET}      : Replaced with (batcat/bat)
check-reboot:${_C_YELLOW}check-reboot${_C_RESET} : Check Reboot Status
ga :${_C_YELLOW}ga${_C_RESET}       : Git Add (git add)
gb:${_C_YELLOW}gb${_C_RESET}       : Git Show Branches (git branch -a)
gc :${_C_YELLOW}gc${_C_RESET}       : Git Commit (git commit -m)
gl:${_C_YELLOW}gl${_C_RESET}       : Git Log Graph (git log --graph ...)
glf :${_C_YELLOW}glf${_C_RESET}      : Git Log File (git log --follow ...)
gp:${_C_YELLOW}gp${_C_RESET}       : Git Push (git push)
gs:${_C_YELLOW}gs${_C_RESET}       : Git Status (git status -sb)
ip :${_C_YELLOW}ip${_C_RESET}       : IP with color (ip -c)
l:${_C_YELLOW}l${_C_RESET}        : List simple (eza -F ...)
la:${_C_YELLOW}la${_C_RESET}       : List All detailed (eza -al ...)
ld:${_C_YELLOW}ld${_C_RESET}       : List Directories (eza -Dhal ...)
lg:${_C_YELLOW}lg${_C_RESET}       : Lazygit (lazygit)
ll:${_C_YELLOW}ll${_C_RESET}       : List Long (eza -lbGF ...)
ls:${_C_YELLOW}ls${_C_RESET}       : Replaced with eza
lt:${_C_YELLOW}lt${_C_RESET}       : List Tree (eza --tree ...)
myip:${_C_YELLOW}myip${_C_RESET}     : Public IP (curl ipinfo.io/ip)
nano :${_C_YELLOW}nano${_C_RESET}     : Replaced with micro
ports:${_C_YELLOW}ports${_C_RESET}    : List Ports (ss -tulpn ...)
psa:${_C_YELLOW}psa${_C_RESET}      : Process List (ps -eo ...)
rm :${_C_YELLOW}rm${_C_RESET}       : Safe RM (rm -i)
t:${_C_YELLOW}t${_C_RESET}        : Tmux Session (tmux_launch)
update:${_C_YELLOW}update${_C_RESET}   : System Update (apt update ...)
vim :${_C_YELLOW}vim${_C_RESET}      : Replaced with Neovim
EOF
  )

  if [[ -n "$selected" ]]; then
    local cmd
    cmd=${selected%%:*}

    # Check if the command ends with a space (indicating input is required)
    if [[ "$cmd" =~ \ $ ]]; then
      # Input required: Paste to prompt for editing
      READLINE_LINE="${cmd}"
      READLINE_POINT=${#cmd}
    else
      # No input required: Execute immediately
      eval "$cmd"
      history -s "$cmd"
    fi
  fi
}

# show_keybinding_cheatsheet
# Purpose: Display a cheatsheet of custom keybindings defined in this file
# Usage: Bound to Alt+x /
show_keybinding_cheatsheet() {
  # Define base options
  local fzf_opts=("${_FZF_CHEATSHEET_OPTS[@]}" --border-label=' Bindings Cheatsheet (Prefix: Alt+x) ')
  
  # Add tmux popup options if in tmux, otherwise fallback to height
  if [[ -n "$TMUX" ]]; then
    fzf_opts+=(--tmux "center,60%,60%")
  else
    fzf_opts+=(--height='80%')
  fi

  # Define the list of bindings and commands
  # Key Sequence : Description (Command)
  local selected
  selected=$(cat <<EOF | fzf "${fzf_opts[@]}" "${_FZF_CHEATSHEET_THEME[@]}"
show_keybinding_cheatsheet:${_C_YELLOW}/${_C_RESET}       : Show this Cheatsheet
show_alias_cheatsheet:${_C_YELLOW}?${_C_RESET}       : Show Alias Cheatsheet
clear:${_C_YELLOW}Alt+x${_C_RESET}   : Clear Screen (this requires Alt+x twice)
dv-find.sh:${_C_YELLOW}e${_C_RESET}       : Find File and Open in Editor - nvim
dv-fif.sh:${_C_YELLOW}f${_C_RESET}       : Find text in Files (fif)
fhistory:${_C_YELLOW}r${_C_RESET}       : (R)ecent Command History
dv-man.sh:${_C_YELLOW}m${_C_RESET}       : Find Manual Pages (fman)
dv-kill.sh:${_C_YELLOW}k${_C_RESET}       : Process Killer (dv-kill)
lg:${_C_YELLOW}g g${_C_RESET}     : Git GUI (lazygit)
fgl:${_C_YELLOW}g l${_C_RESET}     : Git Log (fgl)
dv-git-branch.sh:${_C_YELLOW}g b${_C_RESET}     : Git Branch (dv-git-branch)
dv-git-history.sh:${_C_YELLOW}g h${_C_RESET}     : Git File History (dv-git-history)
tmux_launch:${_C_YELLOW}t${_C_RESET}       : Launch Tmux (main)
EOF
  )

  if [[ -n "$selected" ]]; then
    local cmd
    cmd=${selected%%:*}
    eval "$cmd"
  fi
}

# Bind Alt+x Alt+x to the standard 'clear-screen' readline command.
bind '"\ex\ex":clear-screen'

# Bind Ctrl+x to clear the screen (executes 'clear').
bind -x '"\C-x":clear'

# Bind Alt+x e to dv-find (find file and open in editor - nvim).
bind -x '"\exe":dv-find.sh'

# Bind Alt+x f to dv-fif (find in files).
bind -x '"\exf":dv-fif.sh'

# Bind Alt+x r to fhistory.
bind -x '"\exr":fhistory'

# Bind Alt+x m to dv-man.
bind -x '"\exm":dv-man.sh'

# Bind Alt+x / to the key bind cheatsheet.
bind -x '"\ex/": show_keybinding_cheatsheet'

# Bind Alt+x ? to the alias cheatsheet.
bind -x '"\ex?": show_alias_cheatsheet'

# Bind Alt+x k to dv-kill.
bind -x '"\exk": dv-kill.sh'

# Bind Alt+x g l to the fgl function.
bind -x '"\exgl": fgl'

# Bind Alt+x g b to dv-git-branch.
bind -x '"\exgb": _require_git_repo && dv-git-branch.sh'

# Bind Alt+x g h to dv-git-history.
bind -x '"\exgh": _require_git_repo && dv-git-history.sh'

# Bind Alt+x g g to 'lg' (lazygit).
bind -x '"\exgg": lazygit'

# Bind Alt+x t to tmux_launch.
bind -x '"\ext": tmux_launch'
# Bind Alt+x g b to dv-git-branch.
bind -x '"\exgb": _require_git_repo && dv-git-branch.sh'

# Bind Alt+x g h to dv-git-history.
bind -x '"\exgh": _require_git_repo && dv-git-history.sh'

# Bind Alt+x g g to 'lg' (lazygit).
bind -x '"\exgg": lazygit'

# Bind Alt+x t to tmux_launch.
bind -x '"\ext": tmux_launch'
