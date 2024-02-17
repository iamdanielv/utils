#!/usr/bin/bash

# Check if we are currently running as daniel
# if not, try to switch to daniel using sudo
echo "This is run as $USER"

if ! [ "${USER}" == "daniel" ]
then
    echo "tyring to switch to daniel"
    sudo -H -u daniel bash -c './usercheck.sh'
else
    echo "found user ${USER}, exiting"
    exit;
fi
