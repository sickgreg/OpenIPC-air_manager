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
if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges. Please run with sudo."
    exit 1
fi

# ── Parameter parsing ─────────────────────────────────────────────────────────
IP="10.5.0.10"
CHANNEL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --set-channel|-c)
            [[ $# -ge 2 ]] || { echo "Missing value for --set-channel"; usage; exit 1; }
            CHANNEL="$2"
            # crude numeric check
            [[ "$CHANNEL" =~ ^[0-9]+$ ]] || { echo "Channel must be an integer"; exit 1; }
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            IP="$1"
            shift
            ;;
    esac
done

# ── Common vars ───────────────────────────────────────────────────────────────
export SSHPASS='12345'          # exported once, reused everywhere
SSH_OPTS="-o StrictHostKeyChecking=no"

# ── Host-key house-keeping ────────────────────────────────────────────────────
for KH_FILE in /home/radxa/.ssh/known_hosts /root/.ssh/known_hosts; do
    [[ -f $KH_FILE ]] && ssh-keygen -f "$KH_FILE" -R "$IP" >/dev/null 2>&1 || true
done

mkdir -p /root/.ssh
ssh-keyscan -H "$IP" 2>/dev/null >> /root/.ssh/known_hosts || true

# ── Local file permissions ────────────────────────────────────────────────────
echo "chmod +x on relevant files ..."
chmod -R +x vtx/usr/bin/*
chmod -R +x vrx/usr/local/bin/*
chmod +x air_man_cmd.sh video_mode_chooser.sh

# ── Stop target services (ignore ‘process not found’) ─────────────────────────
echo "Stopping running services on $IP ..."
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'killall -q majestic   || true' 2>&1 | grep -v debug1
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'killall -q alink_drone || true' 2>&1 | grep -v debug1
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'killall -q air_man     || true' 2>&1 | grep -v debug1

# ── Copy payload to device ────────────────────────────────────────────────────
echo "Starting scp ..."
sshpass -e scp $SSH_OPTS -v -r -p vtx/usr/*      root@"$IP":/usr/      2>&1 | grep -v debug1
sshpass -e scp $SSH_OPTS -v -r -p vtx/etc/*      root@"$IP":/etc/      2>&1 | grep -v debug1
sshpass -e scp $SSH_OPTS -v    -p air_man_cmd.sh root@"$IP":/usr/bin/  2>&1 | grep -v debug1

# ── Optional channel configuration ────────────────────────────────────────────
if [[ -n "$CHANNEL" ]]; then
    echo "Setting wireless channel to $CHANNEL ..."
    sshpass -e ssh $SSH_OPTS root@"$IP" \
        "yaml-cli -i /etc/wfb.yaml -s .wireless.channel $CHANNEL" 2>&1 | grep -v debug1
fi

# ── Reboot target ─────────────────────────────────────────────────────────────
echo "SCP completed … rebooting … wait for reconnect..."
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'reboot' 2>&1 | grep -v debug1

# ── Local side: copy VRX files ────────────────────────────────────────────────
echo "Copying VRX files locally..."
cp -f vrx/usr/local/bin/*  /usr/local/bin/
cp -f video_mode_chooser.sh /usr/local/bin/
cp -f video_modes_imx*      /etc/

# ── Countdown before reconnect ────────────────────────────────────────────────
echo "Reconnecting in 25 s..."
for i in $(seq 25 -1 1); do
    printf "\r%d seconds remaining..." "$i"
    sleep 1
done
echo ""

# ── Interactive SSH session ───────────────────────────────────────────────────
sshpass -e ssh $SSH_OPTS root@"$IP"

exit 0
