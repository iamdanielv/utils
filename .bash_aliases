# -------------------
# General Purpose
# -------------------

# Safer 'rm' by prompting for confirmation before deleting.
alias rm='rm -i'

# Use Neovim instead of Vim for a better editing experience.
alias vim='nvim'

# Use micro instead of nano
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

# A compact and graphical view of commit history.
# Using a function for better readability and to handle arguments.
# We unalias 'gl' first to prevent conflicts with any pre-existing alias.
unalias gl 2>/dev/null
gl() {
  # The format string is built as a single argument to --pretty=format.
  local format_string=""
  format_string+="%C(red)%h%Creset %C(bold magenta)%d%Creset%n"
  format_string+="%C(green)%cr %C(blue)%an%Creset%n"
  format_string+=" %C(bold cyan)%s%Creset%n"
  format_string+="%w(72,2,2)%b%Creset"
  git log --graph --pretty=format:"${format_string}%n" "$@"
}

# See the commit history for a specific file, tracking renames.
# Usage: glf <file_path>
unalias glf 2>/dev/null
glf() {
  # The '--' separates log options from file paths.
  git log --follow \
    --pretty=format:'%C(red)%h %C(green)%cr %C(blue)%an %C(bold cyan)%s%Creset' \
    -- "$@"
}

# -------------------
# System, Network & Packages
# -------------------

# Update and upgrade all packages (for Debian/Ubuntu-based systems).
alias update='sudo apt-get update && sudo apt-get upgrade -y'

# Get public IP address from ipinfo.io.
alias myip='curl -s ipinfo.io/ip'

# List all listening TCP and UDP ports.
alias ports='netstat -tulpn'

# For a detailed, tree-like view of all running processes.
alias psa='ps auxf'

# -------------------
# Process Management
# -------------------

# Interactively find and kill a process using fzf.
# We define a helper function for the preview to keep the main command clean.
_fkill_preview() {
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
    c_line="\033[38;5;237m"; # A dim gray for the separator line

    # Print the formatted, colorful output
    printf "%sPID:%s %s%-6s%s %sUser:%s %s%s%s\n", \
      c_blue, c_reset, c_bold, pid, c_reset, c_blue, c_reset, c_bold, user, c_reset;
    printf "%sCPU:%s %s%-6s%s %sMem:%s %s%s%s\n", \
      c_green, c_reset, c_bold, pcpu, c_reset, c_green, c_reset, c_bold, pmem, c_reset;
    printf "%s──────────────────────────────%s\n", c_line, c_reset;
    printf "%s%s%s\n", c_bold, c_cyan, cmd;
  }'
}
# Export the function so fzf's subshell can access it.
export -f _fkill_preview

fkill() {
  # Get a process list with only User, PID, and Command, without headers.
  local processes
  processes=$(ps -eo user,pid,cmd --no-headers | grep -v "fkill")

  local pids
  pids=$(echo "$processes" | fzf -m --height 80% --reverse \
    --header "TAB: mark multiple, ENTER: kill" \
    --preview '_fkill_preview {2}' --preview-window 'wrap,border-left')
  if [[ -n "$pids" ]]; then
    # Extract just the PIDs and kill them. Default signal is SIGTERM.
    echo "$pids" | awk '{print $2}' | xargs kill -s "${1:-TERM}"
  fi
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

# Bind Ctrl+X to the standard 'clear-screen' readline command.
bind '"\C-x":clear-screen'
