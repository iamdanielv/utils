#!/usr/bin/env bash

if [[ $# -ne 1 ]]; then
    exit 2
fi

status=$(git -C "$1" status --porcelain=v2 --branch 2>/dev/null) || exit 0
branch=
commit=
dirty=0

while IFS= read -r line; do
    case "$line" in
        '# branch.head '*) branch=${line#\# branch.head } ;;
        '# branch.oid '*) commit=${line#\# branch.oid } ;;
        1\ *|2\ *|u\ *|?\ *) dirty=1 ;;
    esac
done <<< "$status"

if [[ "$branch" == "(detached)" ]]; then
    branch="@${commit:0:7}"
fi

if [[ -n "$branch" ]]; then
    printf ' %s%s' "$branch" "$([[ $dirty -eq 1 ]] && printf '*')"
fi
