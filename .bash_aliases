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

# A compact and graphical view of commit history.
# Using a function for better readability and to handle arguments.
# We unalias 'gl' first to prevent conflicts with any pre-existing alias.
unalias gl 2>/dev/null
gl() {
  git log --graph --color=always --pretty=format:"${_GIT_LOG_COMPACT_FORMAT}" "$@"
}

# See the commit history for a specific file, tracking renames.
# Usage: glf <file_path>
unalias glf 2>/dev/null
glf() {
  # The '--' separates log options from file paths.
  git log --follow --color=always --pretty=format:"${_GIT_LOG_COMPACT_FORMAT}" -- "$@" | _shorten_git_date
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

    # Highlight the user if it is 'root'
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

# Bind Ctrl+X Ctrl+X to the standard 'clear-screen' readline command.
bind '"\C-x\C-x":clear-screen'

# Bind Ctrl+X Ctrl+K to the fzfkill function for interactive process killing.
bind '"\C-x\C-k":"fzfkill\n"'

# Bind Ctrl+X Ctrl+G Ctrl+L to the fgl function for interactive git log browsing.
bind '"\C-x\C-g\C-l":"fgl\n"'

# Bind Ctrl+X Ctrl+G Ctrl+B to the fgb function for interactive git branch checkout.
bind '"\C-x\C-g\C-b":"fgb\n"'

# Bind Ctrl+X Ctrl+G Ctrl+H to the fzglfh function for interactive file history browsing.
bind '"\C-x\C-g\C-h":"fzglfh \C-e\n"'

# -------------------
# Git with FZF
# -------------------

# Interactively browse git logs with fzf.
# Press 'enter' to view the full diff of a commit.
# Press 'ctrl-y' to print the commit hash and exit.
fgl() {
  local current_branch
  current_branch=$(git branch --show-current)
  export current_branch

  git log --color=always \
      --format="${_GIT_LOG_COMPACT_FORMAT}" "$@" |
      _shorten_git_date | fzf --ansi --no-sort --reverse --tiebreak=index --no-hscroll \
      --header 'ENTER: view diff | CTRL-Y: print hash | SHIFT-UP/DOWN: scroll diff' \
      --preview-window 'down,70%,border-top,wrap' \
      --bind 'enter:execute(git show --color=always {1} | less -R)' \
      --bind 'ctrl-y:execute(echo {1})+abort' \
      --preview 'git show --color=always {1}' \
      --header-first \
      --style=full --prompt='Log> ' \
      --input-label ' Filter Commits ' --header-label ' Git Log ' \
      --bind 'result:transform-list-label:
          if [[ -z $FZF_QUERY ]]; then
            echo " Branch: $current_branch "
          else
            echo " $FZF_MATCH_COUNT matches for [$FZF_QUERY] "
          fi' \
      --bind 'focus:transform-preview-label:[[ -n {} ]] && printf " Diff for [%s] " {1}' \
      --color 'border:#6699cc,label:#99ccff,preview-border:#9999cc,preview-label:#ccccff,header-border:#6699cc,header-label:#99ccff'
}

# fgb - fuzzy git branch checkout
fgb() {
  local branches branch current_branch
  current_branch=$(git branch --show-current)
  export current_branch
  # Get all branches, color them, and format them nicely
  branches=$(git for-each-ref --color=always --sort=-committerdate refs/heads/ --format='%(color:green)%(refname:short)%(color:reset) - (%(color:blue)%(committerdate:relative)%(color:reset)) %(color:yellow)%(subject)%(color:reset)')
  
  # Use fzf to select a branch
  branch=$(echo "$branches" | fzf --ansi --no-sort --reverse --tiebreak=index --prompt='Checkout> ' \
    --preview 'git log --oneline --graph --decorate --color=always $(echo {} | cut -d" " -f1)' \
    --header 'ENTER: checkout | SHIFT-UP/DOWN: scroll log' \
    --preview-window 'down,70%,border-top' --header-first \
    --style=full \
    --input-label ' Filter Branches ' --header-label ' Branches ' \
    --bind 'result:transform-list-label:
        if [[ -z $FZF_QUERY ]]; then
          echo " Current: $current_branch "
        else
          echo " $FZF_MATCH_COUNT matches for [$FZF_QUERY] "
        fi
        ' \
    --bind 'focus:transform-preview-label:[[ -n {} ]] && printf " Log for [%s] " $(echo {} | cut -d" " -f1)' \
    --color 'border:#6699cc,label:#99ccff,preview-border:#9999cc,preview-label:#ccccff' \
    --color 'list-border:#669966,list-label:#99cc99,input-border:#996666,input-label:#ffcccc' \
    --color 'header-border:#6699cc,header-label:#99ccff'
  )

  if [[ -n "$branch" ]]; then
    # Extract branch name (the first word) and checkout
    git checkout "$(echo "$branch" | cut -d' ' -f1)"
  fi
}

# fzglfh - fuzzy git log file history
# Usage: fzglfh <file_path>
fzglfh() {
  # 1. Check if we are in a git repository
  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "Error: Not a git repository."
    return 1
  fi

  while true; do
    # 2. Use fzf to select a file, with its history in the preview.
    local selected_file
    selected_file=$(git ls-files | fzf --ansi --reverse --tiebreak=index \
      --header 'ENTER: inspect commits | ESC: quit | SHIFT-UP/DOWN: scroll history' \
      --preview-window 'down,70%,border-top,wrap' \
      --preview 'git log --follow --color=always --format="%C(yellow)%h%C(reset) %C(green)(%cr)%C(reset) %C(bold cyan)%d%C(reset) %s %C(blue)<%an>%C(reset)" -- {} |
                 sed -E "s/ months? ago/ mon/g; s/ weeks? ago/ wk/g; s/ days? ago/ day/g; s/ hours? ago/ hr/g; s/ minutes? ago/ min/g; s/ seconds? ago/ sec/g"' \
      --header-first \
      --style=full --prompt='File> ' \
      --input-label ' Filter Files ' --header-label ' File History Explorer ' \
      --bind 'focus:transform-preview-label:[[ -n {} ]] && printf " History for [%s] " {}' \
      --color 'border:#6699cc,label:#99ccff,preview-border:#9999cc,preview-label:#ccccff,header-border:#6699cc,header-label:#99ccff')

    # If no file is selected (e.g., user pressed ESC), exit the loop.
    if [[ -z "$selected_file" ]]; then
      break
    fi

    # 3. If a file was selected, open a new fzf instance to inspect its commits.
    # Pressing ESC here will just exit this fzf instance and loop back to the file selector.
    ( git log --follow --color=always \
          --format="%C(yellow)%h%C(reset) %C(green)(%cr)%C(reset) %C(bold cyan)%d%C(reset) %s %C(blue)<%an>%C(reset)" \
          -- "$selected_file" |
      sed -E 's/ months? ago/ mon/g; s/ weeks? ago/ wk/g; s/ days? ago/ day/g; s/ hours? ago/ hr/g; s/ minutes? ago/ min/g; s/ seconds? ago/ sec/g' |
      fzf --ansi --no-sort --reverse --tiebreak=index --no-hscroll\
          --header 'ENTER: view diff | ESC: back to files | CTRL-Y: print hash' \
          --preview-window 'down,70%,border-top,wrap' \
          --bind "enter:execute(git show --color=always {1} -- \"$selected_file\" | less -R)" \
          --bind 'ctrl-y:execute(echo {1})+abort' \
          --preview "git show --color=always {1} -- \"$selected_file\"" \
          --header-first \
          --style=full --prompt='Commit> ' \
          --input-label ' Filter Commits ' --header-label " History for $selected_file " \
          --bind "focus:transform-preview-label:[[ -n {} ]] && printf \" Diff for [%s] \" {1}" \
          --color 'border:#6699cc,label:#99ccff,preview-border:#9999cc,preview-label:#ccccff,header-border:#6699cc,header-label:#99ccff' )
  done
}
