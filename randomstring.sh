#!/bin/bash
# Generate 3 random strings of length 5

for i in {1..3}
do
  echo "$(< /dev/urandom tr -dc a-f0-9 | head -c5)"
done
