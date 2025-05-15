#!/bin/sh

if [ -z "$1" ]; then
    echo "Usage: $0 <drone_ip>"
    exit 1
fi

DRONE_IP="$1"

echo "Fetching current video mode from $DRONE_IP..."
CURRENT=$(air_man_gs "$DRONE_IP" "get_current_video_mode")
echo "Current mode: $CURRENT"
echo

echo "Fetching available video modes..."
MODES=$(air_man_gs "$DRONE_IP" "get_all_video_modes")

if [ -z "$MODES" ]; then
    echo "No video modes received."
    exit 1
fi

# Convert modes into an array
IFS='
'
set -f
MODE_LIST=$(echo "$MODES" | sed '/^[[:space:]]*$/d')  # remove empty lines

i=1
echo "Available video modes:"
for mode in $MODE_LIST; do
    echo "[$i] $mode"
    eval "MODE_$i=\"\$mode\""
    i=$((i + 1))
done

echo
echo -n "Enter the number of the mode you want to set: "
read CHOICE

eval "SELECTED=\$MODE_$CHOICE"

if [ -z "$SELECTED" ]; then
    echo "Invalid choice."
    exit 1
fi

echo "Setting mode: $SELECTED"
air_man_gs "$DRONE_IP" "set_simple_video_mode '$SELECTED'"
