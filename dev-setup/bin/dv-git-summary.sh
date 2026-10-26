#!/usr/bin/env bash
# ===============
# Script Name: dv-git-summary.sh
# Description: Read-only summary of the current Git repository.
# Dependencies: git
# ===============

set -euo pipefail

script_dir=$(dirname "$(readlink -f "$0")")
source "$script_dir/dv-common.sh"

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_GRAY=$'\033[38;5;244m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'

if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
    C_RESET=''
    C_BOLD=''
    C_GRAY=''
    C_GREEN=''
    C_RED=''
    C_YELLOW=''
    C_CYAN=''
fi

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [--pause] [--help]

Show the current repository, branch and upstream, working-tree changes,
latest commit, and stash count.
  --pause  Wait for Enter before exiting (useful in transient popups).
EOF
}

print_section() {
    printf '%b%s%b\n' "$C_BOLD$C_CYAN" "$1" "$C_RESET"
}

print_field() {
    printf '%b│%b  %-12s %b%s%b\n' "$C_CYAN" "$C_RESET" "$1" "$2" "$3" "$C_RESET"
}

pause_after_summary=false
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --pause)
            pause_after_summary=true
            ;;
        *)
            print_usage >&2
            exit 2
            ;;
    esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Error: Not a git repository\n' >&2
    exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
repo_name=$(basename "$repo_root")
if current_branch=$(git symbolic-ref --quiet --short HEAD); then
    branch_label="$current_branch"
else
    branch_label="$(git rev-parse --short HEAD) (detached)"
fi

staged=0
unstaged=0
untracked=0
status_counts=$(
    git status --porcelain=v1 --untracked-files=all -z |
        {
            while IFS= read -r -d '' entry; do
                status="${entry:0:2}"
                if [[ "$status" == "??" ]]; then
                    ((untracked += 1))
                else
                    [[ "${status:0:1}" != " " ]] && ((staged += 1))
                    [[ "${status:1:1}" != " " ]] && ((unstaged += 1))
                fi

                if [[ "$status" == *R* || "$status" == *C* ]]; then
                    IFS= read -r -d '' _ || true
                fi
            done
            printf '%s %s %s\n' "$staged" "$unstaged" "$untracked"
        }
)
read -r staged unstaged untracked <<< "$status_counts"

if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
    read -r ahead behind <<< "$(git rev-list --left-right --count "HEAD...@{upstream}")"
    upstream_label="$upstream (ahead $ahead, behind $behind)"
else
    upstream_label="none"
fi

if git rev-parse --verify --quiet HEAD >/dev/null; then
    IFS=$'\x1f' read -r last_hash last_subject last_age < <(
        git log -1 --format='%h%x1f%s%x1f%cr'
    )
else
    last_hash=''
    last_subject="(no commits yet)"
    last_age=''
fi
stash_count=$(git stash list | wc -l)

if [[ "$upstream_label" == "none" ]]; then
    sync_label="No upstream configured"
    sync_color="$C_GRAY"
else
    if (( ahead == 0 && behind == 0 )); then
        sync_label="✓ Branch matches upstream"
        sync_color="$C_GREEN"
    else
        sync_label=""
        if (( ahead > 0 )); then
            sync_label="$ahead ahead"
        fi
        if (( behind > 0 )); then
            if [[ -n "$sync_label" ]]; then
                sync_label+=", "
            fi
            sync_label+="$behind behind"
        fi
        sync_color="$C_YELLOW"
    fi
fi

printf '%b╭─ Git Summary: %b%s%b\n' \
    "$C_BOLD$C_CYAN" "$sync_color" "$sync_label" "$C_RESET"
printf '%b│%b  %b%-12s%b %s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "Repository" "$C_RESET" "$repo_name"
printf '%b│%b  %b%-12s%b %s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "Path" "$C_RESET" "$repo_root"
printf '%b│%b  %b%-12s%b %s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "Branch" "$C_RESET" "$branch_label"
print_field "Upstream" "$C_CYAN" "${upstream:-none}"

if (( staged == 0 && unstaged == 0 && untracked == 0 )); then
    printf '%b├─ Working Tree:%b %b✓ clean%b\n' \
        "$C_BOLD$C_CYAN" "$C_RESET" "$C_GREEN" "$C_RESET"
else
    printf '%b├─ Working Tree:%b %b● changes%b' \
        "$C_BOLD$C_CYAN" "$C_RESET" "$C_YELLOW" "$C_RESET"
    if (( staged > 0 )); then
        printf '  %b│%b  %bStaged:%b %s' "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$staged"
    fi
    if (( unstaged > 0 )); then
        printf '  %b│%b  %bUnstaged:%b %s' "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$unstaged"
    fi
    if (( untracked > 0 )); then
        printf '  %b│%b  %bUntracked:%b %s' "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$untracked"
    fi
    printf '\n'
fi

print_section "├─ Recent Activity"
printf '%b│%b  %b%s%b %b%s%b\n' "$C_CYAN" "$C_RESET" "$C_GREEN" "$last_hash" "$C_RESET" \
    "$C_BOLD" "$last_subject" "$C_RESET"
if [[ -n "$last_age" ]]; then
    printf '%b│%b  %b%s%b\n' "$C_CYAN" "$C_RESET" "$C_GRAY" "$last_age" "$C_RESET"
fi
if (( stash_count == 1 )); then
    printf '%b╰%b  %-12s %b%s%b\n' "$C_CYAN" "$C_RESET" "Stashes" "$C_YELLOW" "1 stash" "$C_RESET"
else
    printf '%b╰%b  %-12s %b%s%b\n' "$C_CYAN" "$C_RESET" "Stashes" "$C_YELLOW" "$stash_count stashes" "$C_RESET"
fi

if [[ "$pause_after_summary" == true ]]; then
    read -r -p "Press Enter to close..."
fi
