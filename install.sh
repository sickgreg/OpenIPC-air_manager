#!/bin/sh

# Ensure the script is run with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges. Please run with sudo."
    exit 1
fi

# Use the first argument as IP if supplied, otherwise default to 10.5.0.10
IP="${1:-10.5.0.10}"
ssh-keygen -f '/home/radxa/.ssh/known_hosts' -R "$IP"

echo "chmod +x on relevant files ..."
chmod -R +x vtx/usr/bin/*
chmod -R +x vrx/usr/bin/*
chmod +x air_man_cmd.sh
chmod +x video_mode_chooser.sh


echo "Stopping running services..."
SSHPASS="12345" sshpass -e ssh -o StrictHostKeyChecking=no -t root@"$IP" 'killall -q majestic' 2>&1 | grep -v debug1
SSHPASS="12345" sshpass -e ssh -o StrictHostKeyChecking=no -t root@"$IP" 'killall -q alink_drone' 2>&1 | grep -v debug1
SSHPASS="12345" sshpass -e ssh -o StrictHostKeyChecking=no -t root@"$IP" 'killall -q air_man' 2>&1 | grep -v debug1

echo "Starting scp ..."
SSHPASS="12345" sshpass -e scp -o StrictHostKeyChecking=no -v -r -p vtx/usr/* root@"$IP":/usr/ 2>&1 | grep -v debug1
SSHPASS="12345" sshpass -e scp -o StrictHostKeyChecking=no -v -r -p vtx/etc/* root@"$IP":/etc/ 2>&1 | grep -v debug1
SSHPASS="12345" sshpass -e scp -o StrictHostKeyChecking=no -v -r -p air_man_cmd.sh root@"$IP":/usr/bin/ 2>&1 | grep -v debug1

echo "Scp completed ... rebooting ... wait for reconnect..."
SSHPASS="12345" sshpass -e ssh -o StrictHostKeyChecking=no -t root@"$IP" 'reboot' 2>&1 | grep -v debug1

echo "Copying VRX files..."
cp -f vrx/usr/bin/* /usr/bin/
cp -f video_mode_chooser.sh /usr/bin/
cp -f video_modes_imx* /etc/

echo "Reconnecting in 25s..."
# Visual countdown using a loop and printf
for i in $(seq 25 -1 1); do
    printf "\r%d seconds remaining..." "$i"
    sleep 1
done
echo ""

SSHPASS="12345" sshpass -e ssh -o StrictHostKeyChecking=no root@"$IP"

exit 0
