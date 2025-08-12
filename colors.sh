#!/bin/bash

T_RESET='\e[0m'

use_blocks=0
if [[ "$1" == "-b" ]]; then
    use_blocks=1
fi

block_char="█ "

# Loop through all 256 colors
for i in {0..255}; do
    # Set the foreground color using the current color number
    if [[ $use_blocks -eq 1 ]]; then
        printf "\x1b[38;5;%dm%s" "${i}" "${block_char}"
    else
        printf "\x1b[38;5;%dm%3d " "${i}" "${i}"
    fi
    
    # group items
    if (( (i +1) % 8 == 0 )); then
        printf " %s\n" "${i}"
    fi
done

# Reset the color at the end
echo -e "${T_RESET}"