#!/bin/sh
# auto_bitrate.sh  <bitrate-kbps>
# Example:  auto_bitrate.sh 12000

BITRATE="$1"
[ -z "$BITRATE" ] && { echo "Usage: $0 <bitrate-kbps>"; exit 1; }

# 1) Get the lowest-MCS mode that fits this bitrate (key only)
MODE_KEY=$(datalink_manager.sh --get-auto "$BITRATE" | awk '{print $1}')

if [ -z "$MODE_KEY" ]; then
  echo "Failed to find a link mode for ${BITRATE} kbps"
  exit 1
fi
echo "Selected mode: $MODE_KEY"

# 2) Apply the link mode
datalink_manager.sh --set "$MODE_KEY" || {
  echo "Failed to apply mode $MODE_KEY"
  exit 1
}

# 3) Update the encoder / video bitrate
curl -s "http://localhost/api/v1/set?video0.bitrate=${BITRATE}" >/dev/null \
  && echo "Video bitrate set to ${BITRATE} kbps"

echo "Done."
