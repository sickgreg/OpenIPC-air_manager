#!/bin/bash
#
# Provision / update script with safe host-key reset
# + optional --set-channel <N>
#

set -euo pipefail

# ── Usage helper ──────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: sudo $0 [IP] [--set-channel N]

Arguments:
  IP                Target host IP (default: 10.5.0.10)
  --set-channel N   Integer wireless channel to set via yaml-cli
EOF
}

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { echo "This script requires root privileges. Run with sudo."; exit 1; }

# ── Parameter parsing ─────────────────────────────────────────────────────────
IP="10.5.0.10"
CHANNEL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --set-channel|-c)
            [[ $# -ge 2 ]] || { echo "Missing value for --set-channel"; usage; exit 1; }
            CHANNEL="$2"
            [[ "$CHANNEL" =~ ^[0-9]+$ ]] || { echo "Channel must be an integer"; exit 1; }
            shift 2
            ;;
        --help|-h)
            usage; exit 0;;
        *)
            IP="$1"; shift;;
    esac
done

# ── [MOD] Auto-detect channel if not provided ────────────────────────────────
if [[ -z "$CHANNEL" ]]; then
    if [[ -f /etc/wifibroadcast.cfg ]]; then
        CHANNEL=$(grep -i 'wifi_channel' /etc/wifibroadcast.cfg | head -n1 | sed -E 's/.*wifi_channel\s*=\s*"?([^"]+)"?.*/\1/')
        if [[ -z "$CHANNEL" ]]; then
            echo "Could not extract wifi_channel from /etc/wifibroadcast.cfg"; exit 1
        fi
        echo "Detected local wifi_channel: $CHANNEL"
    else
        echo "/etc/wifibroadcast.cfg not found and no --set-channel provided"; exit 1
    fi
fi

# ── Common vars ───────────────────────────────────────────────────────────────
export SSHPASS='12345'
SSH_OPTS="-o StrictHostKeyChecking=no"

# ── Host-key house-keeping ────────────────────────────────────────────────────
for KH_FILE in /home/radxa/.ssh/known_hosts /root/.ssh/known_hosts; do
    [[ -f $KH_FILE ]] && ssh-keygen -f "$KH_FILE" -R "$IP" >/dev/null 2>&1 || true
done
mkdir -p /root/.ssh
ssh-keyscan -H "$IP" 2>/dev/null >> /root/.ssh/known_hosts || true

# ── Local file permissions ────────────────────────────────────────────────────
echo "chmod +x on relevant files ..."
chmod -R +x vtx/usr/bin/* vtx/bin/*
chmod -R +x vrx/usr/local/bin/*

# ── Stop target services ──────────────────────────────────────────────────────
echo "Stopping running services on $IP ..."
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'killall -q majestic   || true' 2>&1 | grep -v debug1 || true
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'killall -q alink_drone || true' 2>&1 | grep -v debug1 || true
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'killall -q air_man     || true' 2>&1 | grep -v debug1 || true

# ── Copy payload to device ────────────────────────────────────────────────────
echo "Starting scp ..."
sshpass -e scp $SSH_OPTS -v -r -p vtx/usr/*      root@"$IP":/usr/     2>&1 | grep -v debug1 || true
sshpass -e scp $SSH_OPTS -v -r -p vtx/bin/*      root@"$IP":/bin/     2>&1 | grep -v debug1 || true
sshpass -e scp $SSH_OPTS -v -r -p vtx/etc/*      root@"$IP":/etc/     2>&1 | grep -v debug1 || true

# ── Channel configuration ─────────────────────────────────────────────────────
if [[ -n "$CHANNEL" ]]; then
    echo "Setting wireless channel to $CHANNEL ..."
    sshpass -e ssh $SSH_OPTS root@"$IP" \
        "yaml-cli -i /etc/wfb.yaml -s .wireless.channel $CHANNEL"
fi

# ── Reboot target ─────────────────────────────────────────────────────────────
echo "SCP completed … rebooting … "
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'reboot' 2>&1 | grep -v debug1 || true

# ── Local side: copy VRX files ────────────────────────────────────────────────
echo "Copying VRX files locally..."
cp -f vrx/usr/local/bin/*  /usr/local/bin/
curl -L -o alink_install.sh https://raw.githubusercontent.com/OpenIPC/adaptive-link/refs/heads/main/alink_install.sh
chmod +x alink_install.sh
./alink_install.sh gs remove
./alink_install.sh gs install

echo -e "\n\nRemember to set:\n\nwlan_adapter\nalink\nstbc and ldpc\n\n...in /etc/wfb.yaml\n"
echo -e "VTX rebooting...  Consider debug via Ethernet if connection lost\n\n"

exit 0

