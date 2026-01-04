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

# Safer 'rm' by prompting for confirmation before deleting.
alias rm='rm -i'

# Use Neovim instead of Vim for a better editing experience.
if command -v nvim &>/dev/null; then
  alias vim='nvim'
fi

# Use micro as a modern replacement for nano
if command -v micro &>/dev/null; then
  alias nano='micro'
fi

# Use 'batcat' (or 'bat') for a 'cat' with syntax highlighting.
if command -v batcat &>/dev/null; then
  alias cat='batcat'
elif command -v bat &>/dev/null; then
  alias cat='bat'
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

# A compact, one-line format for git log commands.
_GIT_LOG_COMPACT_FORMAT='%C(yellow)%h%C(reset) %C(green)(%cr)%C(reset)%C(bold cyan)%d%C(reset) %s %C(blue)<%an>%C(reset)'

# A helper function to shorten the relative date output from git log.
# Takes log output via stdin and pipes it through sed.
_shorten_git_date() {
  sed -E 's/ months? ago/ mon/g; s/ weeks? ago/ wk/g; s/ days? ago/ day/g; s/ hours? ago/ hr/g; s/ minutes? ago/ min/g; s/ seconds? ago/ sec/g'
}
# Export the function so it's available to subshells, like those used by fzf's preview.
export -f _shorten_git_date

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
  git log --graph --color=always --pretty=format:"${_GIT_LOG_COMPACT_FORMAT}" "$@"
}

# See the commit history for a specific file, tracking renames.
# Usage: glf <file_path>
unalias glf 2>/dev/null
glf() {
  _require_git_repo || return 1
  # The '--' separates log options from file paths.
  git log --follow --color=always --pretty=format:"${_GIT_LOG_COMPACT_FORMAT}" -- "$@"
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
  _require_git_repo || return 1
  local current_branch
  current_branch=$(git branch --show-current)

  local selected
  selected=$(git log --color=always \
      --format="${_GIT_LOG_COMPACT_FORMAT}" "$@" |
      _shorten_git_date | fzf "${_FZF_COMMON_OPTS[@]}" --no-sort --no-hscroll \
      --header $'ENTER: view diff | CTRL-Y: pick hash\nSHIFT-UP/DOWN: scroll diff | CTRL-/: view' \
      --border-label=" Git Log: $current_branch " \
      --prompt='  Log❯ ' \
      --bind 'enter:execute(git show --color=always {1} | less -R)' \
      --bind 'ctrl-y:accept' \
      --preview 'git show --color=always {1}' \
      --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_FZF_LBL_STYLE} Diff for [%s] ${_FZF_LBL_RESET}\" {1}")

  _handle_git_hash_selection "$selected"
}

# fgb - Fuzzy Git Branch
# Purpose: Interactively checkout local or remote git branches
# Usage: fgb
fgb() {
  _require_git_repo || return 1
  local current_branch
  current_branch=$(git branch --show-current)

  # Get all branches, color them, and format them nicely
  local branches
  branches=$(git for-each-ref --color=always --sort=-committerdate refs/heads/ refs/remotes/ \
    --format='%(color:green)%(refname:short)%(color:reset) - (%(color:blue)%(committerdate:relative)%(color:reset)) %(color:yellow)%(subject)%(color:reset)' \
    | grep -v '/HEAD')

  # Use fzf to select a branch
  local branch
  branch=$(echo "$branches" | fzf "${_FZF_COMMON_OPTS[@]}" --no-sort \
    --border-label=' Branch Manager ' \
    --prompt='  Checkout❯ ' \
    --preview "git log --oneline --graph --decorate --color=always \$(echo {} | cut -d\" \" -f1)" \
    --header "Current: $current_branch"$'\nENTER: checkout | ESC: quit\nSHIFT-UP/DOWN: scroll log | CTRL-/: view' \
    --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_FZF_LBL_STYLE} Log for [%s] ${_FZF_LBL_RESET}\" \$(echo {} | cut -d\" \" -f1)"
  )

  if [[ -n "$branch" ]]; then
    # Strip ANSI codes and extract the branch name
    local clean_branch
    clean_branch=$(echo "$branch" | sed $'s/\e\[[0-9;]*m//g' | awk '{print $1}')

    # If it's a local branch, checkout directly.
    if git show-ref --verify --quiet "refs/heads/$clean_branch"; then
      git checkout "$clean_branch"
    else
      # If it's a remote branch, strip the remote prefix (e.g. origin/) to checkout the local tracking branch.
      local target="$clean_branch"
      while read -r remote; do
        if [[ "$clean_branch" == "$remote/"* ]]; then
          target="${clean_branch#"$remote"/}"
          break
        fi
      done < <(git remote)

      # If the local branch already exists, switch to it.
      if git show-ref --verify --quiet "refs/heads/$target"; then
        git checkout "$target"
      else
        # Otherwise, create a new tracking branch.
        # --track handles cases where the branch name might be ambiguous (multiple remotes).
        git checkout --track "$clean_branch"
      fi
    fi
  fi
}

# fzglfh - Fuzzy Git Log File History
# Purpose: Interactively browse commit history of a specific file
# Usage: fzglfh
fzglfh() {
  # 1. Check if we are in a git repository
  _require_git_repo || return 1

  while true; do
    # 2. Use fzf to select a file, with its history in the preview.
    local selected_file
    selected_file=$(git ls-files | fzf "${_FZF_COMMON_OPTS[@]}" \
      --header $'ENTER: inspect commits | ESC: quit\nSHIFT-UP/DOWN: scroll history | CTRL-/: view' \
      --border-label=' File History Explorer ' \
      --preview "git log --follow --color=always --format=\"${_GIT_LOG_COMPACT_FORMAT}\" -- {} | _shorten_git_date" \
      --prompt='  File❯ ' \
      --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_FZF_LBL_STYLE} History for [%s] ${_FZF_LBL_RESET}\" {}")

    # If no file is selected (e.g., user pressed ESC), exit the loop.
    if [[ -z "$selected_file" ]]; then
      break
    fi

    # 3. If a file was selected, open a new fzf instance to inspect its commits.
    # Pressing ESC here will just exit this fzf instance and loop back to the file selector.
    local selected_commit
    selected_commit=$(git log --follow --color=always \
          --format="${_GIT_LOG_COMPACT_FORMAT}" -- "$selected_file" |
          _shorten_git_date | fzf "${_FZF_COMMON_OPTS[@]}" --no-sort --no-hscroll \
          --header $'ENTER: view diff | ESC: back to files\nCTRL-Y: print hash | CTRL-/: view' \
          --border-label " History for $selected_file " \
          --bind "enter:execute(git show --color=always {1} -- \"$selected_file\" | less -R)" \
          --bind 'ctrl-y:accept' \
          --preview "git show --color=always {1} -- \"$selected_file\"" \
          --prompt='  Commit❯ ' \
          --input-label ' Filter Commits ' \
          --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_FZF_LBL_STYLE} Diff for [%s] ${_FZF_LBL_RESET}\" {1}")

    _handle_git_hash_selection "$selected_commit"
  done
}

# -------------------
# System, Network & Packages
# -------------------

# update
# Purpose: Update system packages and check if a reboot is required
# Usage: update
unalias update 2>/dev/null
update() {
  printf "%s%sUpdate%s apt sources...\n" "${_C_BOLD}" "${_C_BLUE}" "${_C_RESET}"
  sudo apt update || return 1
  printf "\n%s%sUpgrade%s apt packages...\n" "${_C_BOLD}" "${_C_MAGENTA}" "${_C_RESET}"
  sudo apt upgrade -y
  printf "\n%s%sAutoremove%s apt packages...\n" "${_C_BOLD}" "${_C_CYAN}" "${_C_RESET}"
  sudo apt autoremove -y
  printf "\n"
  check-reboot
}

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
ports() {
  # Header
  printf "${_C_BOLD}${_C_ULINE}%-1s %-6s %21s %21s %s${_C_RESET}\n" "P" "STATUS" "LOCAL:Port " "REMOTE:Port " "PROGRAM/PID"
  
  ss -tulpn | awk \
    -v c_reset="${_C_RESET}" \
    -v c_green="${_C_GREEN}" \
    -v c_yellow="${_C_YELLOW}" \
    -v c_blue="${_C_BLUE}" \
    -v c_magenta="${_C_MAGENTA}" \
    -v c_cyan="${_C_CYAN}" '

    function split_addr(addr, parts) {
      match(addr, /:[^:]*$/)
      if (RSTART > 0) {
        parts[1] = substr(addr, 1, RSTART-1)
        parts[2] = substr(addr, RSTART)
      } else {
        parts[1] = addr
        parts[2] = ""
      }
    }

    NR > 1 {
      # Shorten Protocol: udp -> U, tcp -> T
      proto=toupper(substr($1, 1, 1))
      c_proto = (proto == "T") ? c_green : c_yellow
      
      state=$2
      if (state == "LISTEN") c_state = c_green
      else if (state == "UNCONN") c_state = c_yellow
      else if (state == "ESTAB") c_state = c_blue
      else c_state = c_magenta

      split_addr($5, l_parts)
      split_addr($6, r_parts)

      # Reconstruct process info from $7 onwards
      proc_info=""
      for (i=7; i<=NF; i++) proc_info = proc_info $i " "
      
      # Clean up: users:(("nginx",pid=123,fd=4))... -> "nginx",pid=123
      sub(/users:\(\(/, "", proc_info)
      sub(/(\),|\)\)).*/, "", proc_info)
      sub(/,fd=[0-9]+/, "", proc_info)
      sub(/ +$/, "", proc_info)
      
      if (proc_info == "") proc_info = "-"

      printf "%s%-1s%s %s%-6s%s %15s%s%-6s%s %15s%s%-6s%s %s%s\n", 
        c_proto, proto, c_reset,
        c_state, state, c_reset,
        l_parts[1], c_cyan, l_parts[2], c_reset,
        r_parts[1], c_cyan, r_parts[2], c_reset,
        c_reset, proc_info
    }
  '
}

# List all running processes with essential columns.
alias psa='ps -eo user,pid,pcpu,pmem,command'

# -------------------
# Process Management
# -------------------

# _fzfkill_preview (Internal)
# Purpose: Generate the preview content for fzfkill
# Usage: _fzfkill_preview <PID>
_fzfkill_preview() {
  local pid=$1

  # Get detailed process info. -ww ensures the command isn't truncated.
  ps -ww -o pid=,user=,pcpu=,pmem=,cmd= -p "$pid" | \
    awk -v cb="${_C_BLUE}" -v cg="${_C_GREEN}" -v cc="${_C_CYAN}" \
        -v cbo="${_C_BOLD}" -v cr="${_C_RESET}" -v cw="${_C_YELLOW}" -v cl="${_C_DARK_GRAY}" '
    {
      pid=$1; user=$2; cpu=$3; mem=$4;

      # Reconstruct command (handle spaces)
      cmd_start = index($0, $5);
      cmd = substr($0, cmd_start);

      # Determine user color
      uc = (user == "root") ? cw : cbo;

      # Format Output
      # PID & User
      printf "%sPID:%s %s%-6s%s %sUser:%s %s%s%s \t", cb, cr, cbo, pid, cr, cb, cr, uc, user, cr;
      # CPU & Mem
      printf "%sCPU:%s %s%-6s%s %sMem:%s %s%s%s\n", cg, cr, cbo, cpu, cr, cg, cr, cbo, mem, cr;
      # Separator
      printf "%s──────────────────────────────────%s\n", cl, cr;
      # Command
      printf "%s%s%s\n", cbo, cc, cmd;
    }'
}
# Export the function so fzf's subshell can access it.
export -f _fzfkill_preview

# fzfkill
# Purpose: Interactively find and kill processes
# Usage: fzfkill
fzfkill() {
  # Get a process list with only User, PID, and Command, without headers.
  # Exclude the current fzfkill process and its children from the list.
  # Highlight processes run by the 'root' user.
  # Pipe directly to fzf to avoid storing large output in a variable.
  ps -eo user,pid,cmd --no-headers | \
    awk -v c_warn="${_C_YELLOW}" -v c_reset="${_C_RESET}" '{
      if (/fzfkill/ || /ps -eo/) next;
      if ($1 == "root") {
        # Color only username for root processes
        printf "%s%s%s%s\n", c_warn, $1, c_reset, substr($0, length($1) + 1);
      } else {
        print $0;
      }
    }' | \
    _C_BLUE="${_C_BLUE}" _C_GREEN="${_C_GREEN}" _C_CYAN="${_C_CYAN}" \
    _C_BOLD="${_C_BOLD}" _C_RESET="${_C_RESET}" _C_YELLOW="${_C_YELLOW}" \
    _C_DARK_GRAY="${_C_DARK_GRAY}" \
    fzf -m --no-hscroll "${_FZF_COMMON_OPTS[@]}" \
    --preview-label-pos='2' \
    --header $'ENTER: kill (TERM) | CTRL-K: kill (KILL)\nTAB: mark | SHIFT-UP/DOWN: scroll details' \
    --preview '_fzfkill_preview {2}' \
    --prompt='  Filter❯ ' \
    --border-label=' Process Killer ' --input-label ' Filter Processes ' \
    --bind "enter:execute(echo {+2} | xargs -r kill -s TERM)+abort" \
    --bind "ctrl-k:execute(echo {+2} | xargs -r kill -s KILL)+abort" \
    --bind "result:transform-list-label:
        if [[ -z \$FZF_QUERY ]]; then
          echo \" All Processes \"
        else
          echo \" \$FZF_MATCH_COUNT matches for [\$FZF_QUERY] \"
        fi" \
    --bind 'focus:transform-preview-label:[[ -n {} ]] && printf " Details for PID [%s] " {2}' \
    --color 'border:#cc6666,label:#ff9999,preview-border:#cc9999,preview-label:#ffcccc' \
    --color 'header-border:#cc6666,header-label:#ff9999'
}

# -------------------
# File & Directory Listing (using eza)
# -------------------
# NOTE: These aliases require 'eza', a modern 'ls' replacement, to be
#       installed.

if command -v eza &>/dev/null; then
  # Default 'ls' replacement, grouping directories first.
  alias ls='eza --group-directories-first'

  # List only directories in a detailed, human-readable format.
  alias ld='eza -Dhal --no-filesize --smart-group --icons'

  # Long format listing with block size, Git status, and file indicators.
  alias ll='eza -lbGF --group-directories-first'

  # Tree view of the current directory, one level deep, with icons.
  alias lt='eza --tree --level=1 --icons --group-directories-first'

  # Detailed listing, sorted by size, with Git status (using eza).
  # This is a function to improve readability and handle arguments correctly.
  unalias la 2>/dev/null
  function la {
    eza -al --git --smart-group --color=auto --icons \
      --sort=size --group-directories-first "$@"
  }

  # Simple listing with file type indicators (e.g., / for directories).
  alias l='eza --group-directories-first -F'
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
alias tmux='tmux_launch'

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
ag :${_C_YELLOW}ag${_C_RESET}       : Search with ag (ag --pager='less -XFR')
cat :${_C_YELLOW}cat${_C_RESET}      : Cat with syntax highlighting (batcat/bat)
ga :${_C_YELLOW}ga${_C_RESET}       : Git Add (git add)
gb:${_C_YELLOW}gb${_C_RESET}       : Git Show Branches (git branch -a)
gc :${_C_YELLOW}gc${_C_RESET}       : Git Commit (git commit -m)
gl:${_C_YELLOW}gl${_C_RESET}       : Git Log Graph (git log --graph ...)
glf :${_C_YELLOW}glf${_C_RESET}      : Git Log File (git log --follow ...)
gp:${_C_YELLOW}gp${_C_RESET}       : Git Push (git push)
grep :${_C_YELLOW}grep${_C_RESET}     : Grep with color (grep --color=auto -i)
gs:${_C_YELLOW}gs${_C_RESET}       : Git Status (git status -sb)
ip :${_C_YELLOW}ip${_C_RESET}       : IP with color (ip -c)
l:${_C_YELLOW}l${_C_RESET}        : List simple (eza -F ...)
la:${_C_YELLOW}la${_C_RESET}       : List All detailed (eza -al ...)
ld:${_C_YELLOW}ld${_C_RESET}       : List Directories (eza -Dhal ...)
lg:${_C_YELLOW}lg${_C_RESET}       : Lazygit (lazygit)
ll:${_C_YELLOW}ll${_C_RESET}       : List Long (eza -lbGF ...)
ls:${_C_YELLOW}ls${_C_RESET}       : List (eza ...)
lt:${_C_YELLOW}lt${_C_RESET}       : List Tree (eza --tree ...)
myip:${_C_YELLOW}myip${_C_RESET}     : Public IP (curl ipinfo.io/ip)
nano :${_C_YELLOW}nano${_C_RESET}     : Nano replacement (micro)
ports:${_C_YELLOW}ports${_C_RESET}    : List Ports (ss -tulpn ...)
psa:${_C_YELLOW}psa${_C_RESET}      : Process List (ps -eo ...)
rm :${_C_YELLOW}rm${_C_RESET}       : Safe RM (rm -i)
tmux:${_C_YELLOW}tmux${_C_RESET}     : Tmux Session (tmux_launch)
update:${_C_YELLOW}update${_C_RESET}   : System Update (apt update ...)
vim :${_C_YELLOW}vim${_C_RESET}      : Vim replacement (nvim)
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
clear:${_C_YELLOW}Alt+x${_C_RESET}   : Clear Screen (clear)
fzfkill:${_C_YELLOW}k${_C_RESET}       : Process Killer (fzfkill)
lg:${_C_YELLOW}g g${_C_RESET}     : Git GUI (lazygit)
fgl:${_C_YELLOW}g l${_C_RESET}     : Git Log (fgl)
fgb:${_C_YELLOW}g b${_C_RESET}     : Git Branch (fgb)
fzglfh:${_C_YELLOW}g h${_C_RESET}     : Git File History (fzglfh)
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

# Bind Alt+x / to the key bind cheatsheet.
bind -x '"\ex/": show_keybinding_cheatsheet'

# Bind Alt+x ? to the alias cheatsheet.
bind -x '"\ex?": show_alias_cheatsheet'

# Bind Alt+x k to the fzfkill function.
bind -x '"\exk": fzfkill'

# Bind Alt+x g l to the fgl function.
bind -x '"\exgl": fgl'

# Bind Alt+x g b to the fgb function.
bind -x '"\exgb": fgb'

# Bind Alt+x g h to the fzglfh function.
bind -x '"\exgh": fzglfh'

# Bind Alt+x g g to 'lg' (lazygit).
bind -x '"\exgg": lazygit'

# Bind Alt+x t to tmux_launch.
bind -x '"\ext": tmux_launch'
