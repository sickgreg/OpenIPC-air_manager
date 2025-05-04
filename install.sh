#!/bin/bash
#
# Provision / update script with safe host-key reset
# -------------------------------------------------
#  • Removes any stale host key for the target IP from both the
#    radxa *and* root known-hosts files.
#  • Re-adds the fresh key so subsequent runs work even if you
#    later enable StrictHostKeyChecking=yes.
#  • Keeps every other behaviour identical to your original script.
#

set -euo pipefail

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges. Please run with sudo."
    exit 1
fi

# ── Parameters & common vars ──────────────────────────────────────────────────
IP="${1:-10.5.0.10}"       # default IP if none supplied on the command-line
export SSHPASS='12345'     # exported once, reused everywhere
SSH_OPTS="-o StrictHostKeyChecking=no"

# ── Host-key house-keeping ────────────────────────────────────────────────────
for KH_FILE in /home/radxa/.ssh/known_hosts /root/.ssh/known_hosts; do
    if [[ -f $KH_FILE ]]; then
        ssh-keygen -f "$KH_FILE" -R "$IP" >/dev/null 2>&1 || true
    fi
done

# Re-add current key (only to root’s file, which is what the script uses)
mkdir -p /root/.ssh
ssh-keyscan -H "$IP" 2>/dev/null >> /root/.ssh/known_hosts || true

# ── Permissions on local payload files ────────────────────────────────────────
echo "chmod +x on relevant files ..."
chmod -R +x vtx/usr/bin/*
chmod -R +x vrx/usr/local/bin/*
chmod +x air_man_cmd.sh video_mode_chooser.sh

# ── Stop running services on the target ───────────────────────────────────────
echo "Stopping running services..."
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'killall -q majestic'     2>&1 | grep -v debug1
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'killall -q alink_drone'  2>&1 | grep -v debug1
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'killall -q air_man'      2>&1 | grep -v debug1

# ── Copy firmware / binaries to the device ────────────────────────────────────
echo "Starting scp ..."
sshpass -e scp $SSH_OPTS -v -r -p vtx/usr/*      root@"$IP":/usr/       2>&1 | grep -v debug1
sshpass -e scp $SSH_OPTS -v -r -p vtx/etc/*      root@"$IP":/etc/       2>&1 | grep -v debug1
sshpass -e scp $SSH_OPTS -v    -p air_man_cmd.sh root@"$IP":/usr/bin/   2>&1 | grep -v debug1

echo "Scp completed ... rebooting ... wait for reconnect..."
sshpass -e ssh $SSH_OPTS -t root@"$IP" 'reboot' 2>&1 | grep -v debug1

# ── Local side: copy VRX files to this machine ────────────────────────────────
echo "Copying VRX files locally..."
cp -f vrx/usr/local/bin/*  /usr/local/bin/
cp -f video_mode_chooser.sh /usr/local/bin/
cp -f video_modes_imx*      /etc/

# ── Simple countdown before reconnect ─────────────────────────────────────────
echo "Reconnecting in 25s..."
for i in $(seq 25 -1 1); do
    printf "\r%d seconds remaining..." "$i"
    sleep 1
done
echo ""

# ── Interactive SSH session (for confirmation / manual checks) ───────────────
sshpass -e ssh $SSH_OPTS root@"$IP"

exit 0
