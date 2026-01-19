#!/bin/bash
# ===============
# Script Name: dv-kill.sh
# Description: Interactively find and kill processes.
# Keybinding:  Alt+x k
# Config:      bind -x '"\exk": dv-kill.sh'
# Dependencies: fzf, ps, awk
# ===============

# --- Configuration ---
C_RESET=$'\033[0m'
C_BLUE=$'\033[1;34m'
C_GREEN=$'\033[1;32m'
C_CYAN=$'\033[1;36m'
C_BOLD=$'\033[1m'
C_YELLOW=$'\033[1;33m'
C_DARK_GRAY=$'\033[38;5;237m'

FZF_COMMON_OPTS=(
  --ansi --reverse --tiebreak=index --header-first --border=top
  --preview-window 'right,60%,border,wrap'
  --border-label-pos='3'
  --preview-label-pos='3'
  --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)'
  --color 'border:#cc6666,label:#ff9999,preview-border:#cc9999,preview-label:#ffcccc'
  --color 'header-border:#cc6666,header-label:#ff9999'
  --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7'
)

# --- Preview Logic (Recursive Call) ---
if [[ "$1" == "--preview" ]]; then
    pid=$2
    # Get detailed process info. -ww ensures the command isn't truncated.
    ps -ww -o pid=,user=,pcpu=,pmem=,cmd= -p "$pid" | \
      awk -v cb="${C_BLUE}" -v cg="${C_GREEN}" -v cc="${C_CYAN}" \
          -v cbo="${C_BOLD}" -v cr="${C_RESET}" -v cw="${C_YELLOW}" -v cl="${C_DARK_GRAY}" '
      {
        pid=$1; user=$2; cpu=$3; mem=$4;

        # Reconstruct command (handle spaces)
        cmd_start = index($0, $5);
        cmd = substr($0, cmd_start);

        # Determine user color
        uc = (user == "root") ? cw : cbo;

        # Format Output
        printf "%sPID:%s %s%-6s%s %sUser:%s %s%s%s \t", cb, cr, cbo, pid, cr, cb, cr, uc, user, cr;
        printf "%sCPU:%s %s%-6s%s %sMem:%s %s%s%s\n", cg, cr, cbo, cpu, cr, cg, cr, cbo, mem, cr;
        printf "%s──────────────────────────────────%s\n", cl, cr;
        printf "%s%s%s\n", cbo, cc, cmd;
      }'
    exit 0
fi

# --- Main Logic ---

# Get a process list with only User, PID, and Command, without headers.
# Exclude the current script and its children from the list.
# Highlight processes run by the 'root' user.
ps -eo user,pid,cmd --no-headers | \
  awk -v c_warn="${C_YELLOW}" -v c_reset="${C_RESET}" '{
    if (/dv-kill/ || /ps -eo/) next;
    if ($1 == "root") {
      # Color only username for root processes
      printf "%s%s%s%s\n", c_warn, $1, c_reset, substr($0, length($1) + 1);
    } else {
      print $0;
    }
  }' | \
  fzf -m --no-hscroll "${FZF_COMMON_OPTS[@]}" \
  --preview-label-pos='2' \
  --header $'ENTER: kill (TERM) | CTRL-K: kill (KILL)\nTAB: mark | SHIFT-UP/DOWN: scroll details' \
  --preview "$0 --preview {2}" \
  --prompt='  Filter❯ ' \
  --border-label=' Process Killer ' --input-label ' Filter Processes ' \
  --bind "enter:execute(echo {+2} | xargs -r kill -s TERM)+abort" \
  --bind "ctrl-k:execute(echo {+2} | xargs -r kill -s KILL)+abort" \
  --bind "result:transform-list-label: [[ -z \$FZF_QUERY ]] && echo \" All Processes \" || echo \" \$FZF_MATCH_COUNT matches for [\$FZF_QUERY] \"" \
  --bind 'focus:transform-preview-label:[[ -n {} ]] && printf " Details for PID [%s] " {2}'