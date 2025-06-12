#!/usr/bin/bash

# Define the user to switch to
TARGET_USER="daniel"

# Check if we are currently running as TARGET_USER
# if not, try to switch to TARGET_USER using sudo
echo "This is run as $USER"

if ! [ "${USER}" == "${TARGET_USER}" ]
then
    echo -e "Trying to switch to \033[34m${TARGET_USER}...\033[0m"
    # Use sudo to switch user and run the script again
    if sudo -H -u "${TARGET_USER}" bash -c './usercheck.sh'
    then
        echo -e "\033[32m✓ Switched to ${TARGET_USER} successfully\033[0m"
        exit 0
    else
        echo -e "\033[31m✗ Failed to switch to ${TARGET_USER}\033[0m"
        exit 1
    fi
else
    echo -e "\033[32m✓ Found user ${USER}\033[0m, exiting"
    exit 0
fi
