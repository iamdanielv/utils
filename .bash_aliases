# -------------------
# General Purpose
# -------------------

# Better cat
alias cat='batcat'

# Enhanced ag
alias ag="ag --pager='less -XFR'"

# Colorized ip
alias ip="ip -c"

# Colorized and case-insensitive grep
alias grep="grep --color=auto -i"

# -------------------
# Git
# -------------------

# Check the status of git repository
alias gs='git status -sb'

# List all branches in the repository
alias gb='git branch -a'

# Stage files for a commit
alias ga='git add'

# Commit staged files with a message
alias gc='git commit -m'

# Push commits to the remote repository
alias gp='git push'

# A compact and graphical view of commit history
alias gl='git log --oneline --graph --decorate'

# -------------------
# System & Network
# -------------------

# Update and upgrade all packages
alias update='sudo apt-get update && sudo apt-get upgrade -y'

# Get public IP address
alias myip='curl -s ipinfo.io/ip; echo'

# List all listening ports
alias ports='netstat -tulpn'

# For a detailed view of all running processes
alias psa='ps auxf'
