# -------------------
# General Purpose
# -------------------

# Safer 'rm' by prompting for confirmation before deleting.
alias rm='rm -i'

# Use Neovim instead of Vim for a better editing experience.
alias vim='nvim'

# Use micro as a modern replacement for nano
alias nano="micro"

# Use 'batcat' (or 'bat') for a 'cat' with syntax highlighting.
alias cat='batcat'

# Use 'less' as a pager for 'ag' search results.
alias ag="ag --pager='less -XFR'"

# Add color to the output of the 'ip' command.
alias ip="ip -c"

# Always use color and case-insensitive matching for 'grep'.
alias grep="grep --color=auto -i"

# Go up one directory.
alias ..='cd ..'

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

# Shared styles and options for FZF Git functions (fgb, fzglfh)
_GIT_FZF_LBL_STYLE=$'\033[38;2;255;255;255;48;2;45;63;118m'
_GIT_FZF_LBL_RESET=$'\033[0m'

_GIT_FZF_COMMON_OPTS=(
  --ansi --reverse --tiebreak=index --header-first --border=top
  --preview-window 'right,60%,border,wrap'
  --border-label-pos='3'
  --preview-label-pos='3'
  --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)'
  --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff'
  --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7'
)

# Helper to ensure the current directory is a git repository.
_require_git_repo() {
  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    local c_err='\033[38;2;243;139;168m' # Catppuccin Red
    local c_reset='\033[0m'
    printf "%b✗ Error:%b Not a git repository\n" "${c_err}" "${c_reset}"
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

# -------------------
# System, Network & Packages
# -------------------

# Update and upgrade all packages (for Debian/Ubuntu-based systems).
alias update='sudo apt-get update && sudo apt-get upgrade -y && echo "" && check-reboot'

# Check if a system reboot is required.
alias check-reboot='if [ -f /var/run/reboot-required ]; then echo -e "\033[1;31m Reboot Required\033[0m"; else echo -e "\033[1;32m✓ No reboot required\033[0m"; fi'

# Get public IP address from ipinfo.io.
alias myip='curl -s ipinfo.io/ip'

# List all listening TCP and UDP ports.
alias ports='netstat -tulpn'

# List all running processes with essential columns.
alias psa='ps -eo user,pid,pcpu,pmem,command'

# -------------------
# Process Management
# -------------------

# Interactively find and kill a process using fzf.
# We define a helper function for the preview to keep the main command clean.
_fzfkill_preview() {
  # Get detailed process info. -ww ensures the command isn't truncated.
  ps -ww -o pid=,user=,pcpu=,pmem=,cmd= -p "$1" | awk '{
    # Assign fields to variables for clarity
    pid=$1; user=$2; pcpu=$3; pmem=$4;

    # Reconstruct the full command string, which starts at the 5th field
    cmd_start_index = index($0, $5);
    cmd = substr($0, cmd_start_index);

    # Define ANSI color codes for a prettier output
    c_blue="\033[1;34m"; # Bold Blue
    c_green="\033[32m";
    c_cyan="\033[36m";
    c_bold="\033[1m";
    c_reset="\033[0m";
    c_light_red="\033[38;5;11m";
    c_line="\033[38;5;237m"; # A dim gray for the separator line

    # Highlight the user if it is root
    user_color = c_bold;
    if (user == "root") {
      user_color = c_light_red;
    }

    # Print the formatted, colorful output
    printf "%sPID:%s %s%-6s%s %sUser:%s %s%s%s \t", c_blue, c_reset, c_bold, pid, c_reset, c_blue, c_reset, user_color, user, c_reset;
    printf "%sCPU:%s %s%-6s%s %sMem:%s %s%s%s\n", c_green, c_reset, c_bold, pcpu, c_reset, c_green, c_reset, c_bold, pmem, c_reset;
    printf "%s──────────────────────────────────%s\n", c_line, c_reset;
    printf "%s%s%s\n", c_bold, c_cyan, cmd;
  }'
}
# Export the function so fzf's subshell can access it.
export -f _fzfkill_preview

fzfkill() {
  # Get a process list with only User, PID, and Command, without headers.
  # Exclude the current fzfkill process and its children from the list.
  # Highlight processes run by the 'root' user.
  local processes
  processes=$(ps -eo user,pid,cmd --no-headers | grep -v -e "fzfkill" -e "ps -eo" | \
    awk '{
      if ($1 == "root") {
        # Color only username for root processes
        printf "\033[38;5;11m%s\033[0m%s\n", $1, substr($0, length($1) + 1);
      } else {
        print $0;
      }
    }')

  # The fzf command now directly executes the kill command.
  # This allows us to bind different signals to different keys.
  printf "%s" "$processes" | fzf -m --reverse --no-hscroll \
    --ansi --header $'ENTER: kill (TERM) | CTRL-K: kill (KILL) | TAB: mark | SHIFT-UP/DOWN: scroll details' --header-first \
    --preview '_fzfkill_preview {2}' --preview-window 'down,40%,border-top,wrap' \
    --style=full --prompt='Filter> ' \
    --input-label ' Filter Processes ' --header-label ' Process Killer ' \
    --bind 'enter:execute(echo {} | awk "{print \$2}" | xargs -r kill -s TERM)+abort' \
    --bind 'ctrl-k:execute(echo {} | awk "{print \$2}" | xargs -r kill -s KILL)+abort' \
    --bind 'result:transform-list-label:
        if [[ -z $FZF_QUERY ]]; then
          echo " All Processes "
        else
          echo " $FZF_MATCH_COUNT matches for [$FZF_QUERY] "
        fi' \
    --bind 'focus:transform-preview-label:[[ -n {} ]] && printf " Details for PID [%s] " {2}' \
    --color 'border:#cc6666,label:#ff9999,preview-border:#cc9999,preview-label:#ffcccc' \
    --color 'header-border:#cc6666,header-label:#ff9999'
}

# -------------------
# File & Directory Listing (using eza)
# -------------------
# NOTE: These aliases require 'eza', a modern 'ls' replacement, to be
#       installed.

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
la() {
  eza -al --git --smart-group --color=auto --icons \
    --sort=size --group-directories-first "$@"
}

# Simple listing with file type indicators (e.g., / for directories).
alias l='eza --group-directories-first -F'

alias tmux='tmux new-session -AD -s main'

# -------------------
# Interactive Tools & Keybindings
# -------------------

# Interactive cheatsheet for custom keybindings
show_keybinding_cheatsheet() {
  local selected
  local c_key=$'\033[1;33m'
  local c_reset=$'\033[0m'
  # Define base options
  local fzf_opts=(
    --ansi 
    --border=rounded 
    --border-label=' Bindings Cheatsheet (Prefix: Alt+x) ' 
    --border-label-pos='3'
    --layout=reverse 
    --prompt="Run> " 
    --delimiter=":" 
    --with-nth=1,2
  )
  
  # Add tmux popup options if in tmux, otherwise fallback to height
  if [[ -n "$TMUX" ]]; then
    fzf_opts+=(--tmux center,60%,60%)
  else
    fzf_opts+=(--height=80%)
  fi

  # Define the list of bindings and commands
  # Key Sequence : Description (Command)
  local menu_items
  menu_items=$(cat <<EOF
${c_key}/${c_reset}       : Show this Cheatsheet (show_keybinding_cheatsheet)
${c_key}Alt+x${c_reset}   : Clear Screen (clear)
${c_key}k${c_reset}       : Process Killer (fzfkill)
${c_key}g g${c_reset}     : Git GUI (lazygit)
${c_key}g l${c_reset}     : Git Log (fgl)
${c_key}g b${c_reset}     : Git Branch (fgb)
${c_key}g h${c_reset}     : Git File History (fzglfh)
EOF
)

  selected=$(echo "$menu_items" | \
  fzf "${fzf_opts[@]}" \
      --color=bg+:#2d3f76,bg:#1e2030,gutter:#1e2030 \
      --color=fg:#c8d3f5,query:#c8d3f5:regular \
      --color=border:#f9e2af,label:#f9e2af:reverse \
      --color=header:#ff966c,separator:#ff966c \
      --color=info:#545c7e,scrollbar:#589ed7 \
      --color=marker:#ff007c,pointer:#ff007c,spinner:#ff007c \
      --color=prompt:#65bcff)

  if [[ -n "$selected" ]]; then
    local cmd
    cmd=$(echo "$selected" | sed -n 's/.*(\(.*\))/\1/p')
    eval "$cmd"
  fi
}

# Bind Alt+x Alt+x to the standard 'clear-screen' readline command.
bind '"\ex\ex":clear-screen'

# Bind Alt+x / to the cheatsheet.
bind '"\ex/":"show_keybinding_cheatsheet\n"'

# Bind Alt+x k to the fzfkill function.
bind '"\exk":"fzfkill\n"'

# Bind Alt+x g l to the fgl function.
bind '"\exgl":"fgl\n"'

# Bind Alt+x g b to the fgb function.
bind '"\exgb":"fgb\n"'

# Bind Alt+x g h to the fzglfh function.
bind '"\exgh":"fzglfh \C-e\n"'

# Bind Alt+x g g to 'lg' (lazygit).
bind '"\exgg":"lg\n"'

# -------------------
# Git with FZF
# -------------------

# Interactively browse git logs with fzf.
# Press 'enter' to view the full diff of a commit.
# Press 'ctrl-y' to print the commit hash and exit.
fgl() {
  _require_git_repo || return 1
  local current_branch
  current_branch=$(git branch --show-current)

  git log --color=always \
      --format="${_GIT_LOG_COMPACT_FORMAT}" "$@" |
      _shorten_git_date | fzf "${_GIT_FZF_COMMON_OPTS[@]}" --no-sort --no-hscroll \
      --header $'ENTER: view diff | CTRL-Y: print hash\nSHIFT-UP/DOWN: scroll diff | CTRL-/: view' \
      --border-label=" Git Log: $current_branch " \
      --prompt='  Log❯ ' \
      --bind 'enter:execute(git show --color=always {1} | less -R)' \
      --bind 'ctrl-y:execute(echo {1})+abort' \
      --preview 'git show --color=always {1}' \
      --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_GIT_FZF_LBL_STYLE} Diff for [%s] ${_GIT_FZF_LBL_RESET}\" {1}"
}

# fgb - fuzzy git branch checkout
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
  branch=$(echo "$branches" | fzf "${_GIT_FZF_COMMON_OPTS[@]}" --no-sort \
    --border-label=' Branch Manager ' \
    --prompt='  Checkout❯ ' \
    --preview 'git log --oneline --graph --decorate --color=always $(echo {} | cut -d" " -f1)' \
    --header "Current: $current_branch"$'\nENTER: checkout | ESC: quit\nSHIFT-UP/DOWN: scroll log | CTRL-/: view' \
    --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_GIT_FZF_LBL_STYLE} Log for [%s] ${_GIT_FZF_LBL_RESET}\" \$(echo {} | cut -d\" \" -f1)"
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
          target="${clean_branch#$remote/}"
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

# fzglfh - fuzzy git log file history
fzglfh() {
  # 1. Check if we are in a git repository
  _require_git_repo || return 1

  while true; do
    # 2. Use fzf to select a file, with its history in the preview.
    local selected_file
    selected_file=$(git ls-files | fzf "${_GIT_FZF_COMMON_OPTS[@]}" \
      --header $'ENTER: inspect commits | ESC: quit\nSHIFT-UP/DOWN: scroll history | CTRL-/: view' \
      --border-label=' File History Explorer ' \
      --preview "git log --follow --color=always --format=\"${_GIT_LOG_COMPACT_FORMAT}\" -- {} | _shorten_git_date" \
      --prompt='  File❯ ' \
      --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_GIT_FZF_LBL_STYLE} History for [%s] ${_GIT_FZF_LBL_RESET}\" {}")

    # If no file is selected (e.g., user pressed ESC), exit the loop.
    if [[ -z "$selected_file" ]]; then
      break
    fi

    # 3. If a file was selected, open a new fzf instance to inspect its commits.
    # Pressing ESC here will just exit this fzf instance and loop back to the file selector.
    ( git log --follow --color=always \
          --format="${_GIT_LOG_COMPACT_FORMAT}" -- "$selected_file" |
          _shorten_git_date | fzf "${_GIT_FZF_COMMON_OPTS[@]}" --no-sort --no-hscroll \
          --header $'ENTER: view diff | ESC: back to files\nCTRL-Y: print hash | CTRL-/: view' \
          --border-label " History for $selected_file " \
          --bind "enter:execute(git show --color=always {1} -- \"$selected_file\" | less -R)" \
          --bind 'ctrl-y:execute(echo {1})+abort' \
          --preview "git show --color=always {1} -- \"$selected_file\"" \
          --prompt='  Commit❯ ' \
          --input-label ' Filter Commits ' \
          --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_GIT_FZF_LBL_STYLE} Diff for [%s] ${_GIT_FZF_LBL_RESET}\" {1}" )
  done
}
