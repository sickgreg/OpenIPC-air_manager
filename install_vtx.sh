#!/bin/sh

# Use the first argument as IP if supplied, otherwise default to 192.168.1.10
IP="${1:-192.168.1.10}"
ssh-keygen -f '/home/radxa/.ssh/known_hosts' -R "$IP"

echo "chmod +x on relevant files ..."
chmod -R +x usr/bin*
chmod -R +x etc/init.d/*

echo "Stopping running services..."
SSHPASS="12345" sshpass -e ssh -o StrictHostKeyChecking=no -t root@"$IP" 'killall -q alink_drone' 2>&1 | grep -v debug1
SSHPASS="12345" sshpass -e ssh -o StrictHostKeyChecking=no -t root@"$IP" 'killall -q air_man' 2>&1 | grep -v debug1

echo "Starting scp ..."
SSHPASS="12345" sshpass -e scp -o StrictHostKeyChecking=no -O -v -r -p /etc/gs.key root@"$IP":/etc/drone.key 2>&1 | grep -v debug1
SSHPASS="12345" sshpass -e scp -o StrictHostKeyChecking=no -O -v -r -p usr/* root@"$IP":/ 2>&1 | grep -v debug1
SSHPASS="12345" sshpass -e scp -o StrictHostKeyChecking=no -O -v -r -p etc/* root@"$IP":/ 2>&1 | grep -v debug1

echo "Scp completed ... rebooting ... wait for reconnect..."
SSHPASS="12345" sshpass -e ssh -o StrictHostKeyChecking=no -t root@"$IP" 'reboot' 2>&1 | grep -v debug1

echo "Reconnecting in 25s..."
# Visual countdown using a loop and printf
for i in $(seq 25 -1 1); do
    printf "\r%d seconds remaining..." "$i"
    sleep 1
done
echo ""

SSHPASS="12345" sshpass -e ssh -o StrictHostKeyChecking=no root@"$IP"
