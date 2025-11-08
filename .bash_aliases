# -------------------
# General Purpose
# -------------------

# Safer 'rm' by prompting for confirmation before deleting.
alias rm='rm -i'

# Use Neovim instead of Vim for a better editing experience.
alias vim='nvim'

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

# -------------------
# Interactive Tools & Keybindings
# -------------------

# Interactively find a directory using fzf and cd into it.
# Excludes hidden directories and provides a 'tree' preview.
# - Preview can be toggled with Ctrl-V.
# - Invoke this function by pressing Ctrl-F.

# Bind Ctrl+X to the standard 'clear-screen' readline command.
bind '"\C-x":clear-screen'
