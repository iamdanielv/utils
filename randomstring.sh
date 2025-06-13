#!/bin/bash

# Script to generate random hex strings.
#
# Usage:
#   ./randomstring.sh [number_of_strings] [string_length]
#
#   If no arguments are provided, it generates 3 strings of length 5.
#   If one argument is provided, it's treated as the string length,
#   and 3 strings are generated.
#
# Example:
#   ./randomstring.sh 5 10  # Generates 5 strings of length 10
#   ./randomstring.sh       # Generates 3 strings of length 5
#

# Function to generate a random string of specified length using hexadecimal characters.
generate_random_string() {
  local length=$1
  < /dev/urandom tr -dc 'a-f0-9' | head -c "$length"
}

# Validate that the argument is a number.
is_number() {
  [[ $1 =~ ^[0-9]+$ ]]
}

# Default values for number of strings and length.
default_num_strings=3
default_length=5

# Initialize variables with default values.
num_strings=$default_num_strings
length=$default_length

# Process arguments to determine number of strings and length.
if [ $# -ge 1 ]; then
  num_strings=$1
  if ! is_number "$num_strings"; then
    echo "Error: The first parameter must be a number."
    exit 1
  fi
fi

if [ $# -ge 2 ]; then
  length=$2
  if ! is_number "$length"; then
    echo "Error: The second parameter must be a number."
    exit 1
  fi
fi

# Generate and print the random strings.
strings=()
for ((i = 0; i < num_strings; i++)); do
  strings+=("$(generate_random_string $length)")
done

for string in "${strings[@]}"; do
  echo "$string"
done