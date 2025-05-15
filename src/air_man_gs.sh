#!/usr/bin/env bash
set -euo pipefail

# Require root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (use sudo)"
  exit 1
fi

PORT=12355
VERBOSE=0

print_help() {
  cat <<EOF
Usage:
  $0 [--verbose] <server_ip> "<command>"
  $0 --help

Options:
  -v, --verbose   Enable debug output
  -h, --help      Show this help message

Commands (use quotes for multiple words):
  start_alink
  stop_alink
  restart_majestic
  "change_channel <n>"
  confirm_channel_change
  "set_alink_power <0–10>"
  "set_video_mode <size> <fps> <exposure> '<crop>'"
  restart_wfb
  restart_msposd
  (and any air_man_cmd.sh commands)
EOF
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help) print_help; exit 0 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; print_help; exit 1 ;;
    *) break ;;
  esac
done

if [[ $# -lt 2 ]]; then
  print_help; exit 1
fi

SERVER_IP=$1; shift
CMD="$1"

[[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Command → $CMD"

# Translate legacy alias
if [[ $CMD =~ ^set\ air\ wfbng\ air_channel\ ([0-9]+)$ ]]; then
  CMD="change_channel ${BASH_REMATCH[1]}"
  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Alias → $CMD"
fi

##############################
# === set_video_mode ===
##############################
if [[ $CMD =~ ^set_video_mode[[:space:]]+[^[:space:]]+[[:space:]]+([0-9]+) ]]; then
  NEW_FPS="${BASH_REMATCH[1]}"
  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] set_video_mode detected, FPS = $NEW_FPS"

  MAX=3
  for i in $(seq 1 $MAX); do
    [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] set_video_mode attempt $i/$MAX"
    set +e
    RESPONSE=$(printf '%s\n' "$CMD" | nc -w2 "$SERVER_IP" $PORT)
    STAT=$?
    set -e

    if [[ $STAT -eq 0 && -n "$RESPONSE" && "$RESPONSE" != *Failed* ]]; then
      echo "$RESPONSE"

      REC_FPS_FILE="/config/scripts/rec-fps"
      [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Reading existing FPS from $REC_FPS_FILE"

	  CURRENT_FPS=$(grep -E '^\s*fps\s*=' "$REC_FPS_FILE" | cut -d '=' -f2 | tr -dc '0-9')
      [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Previous FPS: '$CURRENT_FPS'"

      if [[ "$CURRENT_FPS" != "$NEW_FPS" ]]; then
        [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] FPS changed to $NEW_FPS: updating file and restarting openipc"

        sed -i -E "s/^(\s*fps\s*=\s*)[0-9]+/\1$NEW_FPS/" "$REC_FPS_FILE"
        systemctl restart openipc
      else
        [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] FPS unchanged: no update or restart needed"
      fi

      exit 0
    fi
    sleep 0.5
  done

  echo "Failed to set video mode after $MAX attempts"
  exit 1
fi


##########################
# === change_channel ===
##########################
if [[ $CMD =~ ^change_channel\ ([0-9]+)$ ]]; then
  CH=${BASH_REMATCH[1]}
  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Sending change_channel $CH"

  MAX_TRIES=3
  SLEEP_BETWEEN=0.5
  RESPONSE_LINES=()

  for (( try=1; try<=MAX_TRIES; try++ )); do
    [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] change_channel attempt $try/$MAX_TRIES"

    mapfile -t RESPONSE_LINES < <(
      {
        printf 'change_channel %d\n' "$CH"
        sleep 2
      } | nc -w3 "$SERVER_IP" $PORT
    )

    if (( ${#RESPONSE_LINES[@]} > 0 )); then
      [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Received reply on attempt $try"
      break
    fi

    [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] No reply yet; sleeping ${SLEEP_BETWEEN}s"
    sleep "$SLEEP_BETWEEN"
  done

  if (( ${#RESPONSE_LINES[@]} == 0 )); then
    echo "No reply from VTX on change_channel after $MAX_TRIES attempts"
    exit 1
  fi

  for line in "${RESPONSE_LINES[@]}"; do
    echo "$line"
    if [[ "$line" == *Failed* ]]; then
      [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] VTX rejected set channel; aborting"
      exit 1
    fi
  done

  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] VTX okay to set new channel → proceeding with local set"

  # Reconfigure NICs
  . /etc/default/wifibroadcast
  RAW_NICS=$WFB_NICS
  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Raw WFB_NICS string: '$RAW_NICS'"

  read -ra NICS <<< "$RAW_NICS"
  [[ $VERBOSE -eq 1 ]] && printf "[DEBUG] Parsed NICS: %s\n" "${NICS[@]}"

  FIRST_NIC="${NICS[0]}"
  ORIG=$(
    iw dev "$FIRST_NIC" info 2>/dev/null | awk '/channel/ {print $2; exit}' || echo "unknown"
  )
  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Original local channel (on $FIRST_NIC): $ORIG"

  RAW_BW_LINE=$(grep -E '^\s*bandwidth' /etc/wifibroadcast.cfg || true)
  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Raw bandwidth line: '$RAW_BW_LINE'"

  BANDWIDTH=$(
    awk -F= '/^\s*bandwidth/ {
      gsub(/[^0-9]/, "", $2)
      print $2
      exit
    }' /etc/wifibroadcast.cfg || echo
  )
  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Parsed BANDWIDTH='$BANDWIDTH'"

  case "$BANDWIDTH" in
    10) MODE="10MHz" ;;
    40) MODE="HT40+" ;;
    80) MODE="80MHz" ;;
    *)  MODE="" ;;
  esac
  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Will use channel mode: '$MODE'"

  for nic in "${NICS[@]}"; do
    if [[ -n "$MODE" ]]; then
      [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] iw dev $nic set channel $CH $MODE"
      iw dev "$nic" set channel "$CH" $MODE
    else
      [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] iw dev $nic set channel $CH"
      iw dev "$nic" set channel "$CH"
    fi
  done

  # Confirm channel change
  SUCCESS=0
  for i in {1..10}; do
    [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Sending confirm_channel_change attempt $i"
    set +e
    CONFIRM=$(printf 'confirm_channel_change\n' | nc -w1 "$SERVER_IP" $PORT)
    RC=$?
    set -e

    if [[ $RC -eq 0 && -n "$CONFIRM" ]]; then
      echo "$CONFIRM"
      SUCCESS=1
      break
    fi

    sleep 0.25
  done

  if [[ $SUCCESS -eq 1 ]]; then
    echo "Got confirmation. Persisting wifi_channel $CH into config"
    sed -i -E "s|^\s*wifi_channel\s*=.*|wifi_channel = $CH|" /etc/wifibroadcast.cfg
  else
    echo "No confirmation received. Reverting local NICs to $ORIG"
    for nic in "${NICS[@]}"; do
      iw dev "$nic" set channel "$ORIG" $MODE
    done
  fi

  exit 0
fi

#############################
# === Simple command ===
#############################
MAX=3
for i in $(seq 1 $MAX); do
  [[ $VERBOSE -eq 1 ]] && echo "[DEBUG] Simple cmd attempt $i/$MAX"
  set +e
  RESPONSE=$(printf '%s\n' "$CMD" | nc -w2 "$SERVER_IP" $PORT)
  STAT=$?
  set -e

  if [[ $STAT -eq 0 && -n "$RESPONSE" ]]; then
    echo "$RESPONSE"
    exit 0
  fi
  sleep 0.5
done

echo "No response from VTX after $MAX attempts"
exit 1
