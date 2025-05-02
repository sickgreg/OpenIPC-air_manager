#!/bin/bash

# Help function
show_help() {
  echo "Usage: $0 <camera_ip> <config_file>"
  echo
  echo "Arguments:"
  echo "  camera_ip      IP address of the camera (e.g., 10.5.0.10)"
  echo "  config_file    Path to the INI-style config file with video mode definitions"
  echo
  echo "Example:"
  echo "  $0 10.5.0.10 video_modes_imx335.ini"
  exit 1
}

# Check for required arguments
if [ -z "$1" ] || [ -z "$2" ]; then
  show_help
fi

camera_ip="$1"
ini_file="$2"

# Declare arrays to store display names and command strings.
declare -a mode_names
declare -a mode_commands

# Read the configuration file line by line.
while IFS= read -r line; do
  trimmed=$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [[ -z "$trimmed" || "$trimmed" == \;* ]]; then
    continue
  fi
  if [[ "$trimmed" =~ ^\"(.*)\"[[:space:]]*=[[:space:]]*\"(.*)\"$ ]]; then
    mode_names+=("${BASH_REMATCH[1]}")
    mode_commands+=("${BASH_REMATCH[2]}")
  fi
done < "$ini_file"

if [ ${#mode_names[@]} -eq 0 ]; then
  echo "No mode commands found in $ini_file"
  exit 1
fi

echo "Select a mode:"
for i in "${!mode_names[@]}"; do
  echo "$((i + 1))) ${mode_names[$i]}"
done

read -p "Enter selection [1-${#mode_names[@]}]: " selection

if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#mode_names[@]}" ]; then
  echo "Invalid selection."
  exit 1
fi

index=$((selection - 1))
selected_command="${mode_commands[$index]}"

executable="air_man_gs"

echo "Executing: $executable $camera_ip \"$selected_command\""

if [ -x "/usr/local/bin/$executable" ]; then
    /usr/local/bin/$executable "$camera_ip" "$selected_command"
elif [ -x "./$executable" ]; then
    ./$executable "$camera_ip" "$selected_command"
else
    echo "Executable '$executable' not found in /usr/local/bin or current directory."
    exit 1
fi
