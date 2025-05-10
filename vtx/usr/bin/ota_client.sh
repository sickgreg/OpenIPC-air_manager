#!/bin/sh

# ── Check dependencies ────────────────────────────────
command -v fw_printenv >/dev/null 2>&1 || {
    echo "Error: fw_printenv not found"
    exit 1
}

command -v sysupgrade >/dev/null 2>&1 || {
    echo "Error: sysupgrade not found"
    exit 1
}

# ── Get firmware upgrade URL ──────────────────────────
fw_url=$(fw_printenv upgrade 2>/dev/null | cut -d= -f2)

if [ -z "$fw_url" ]; then
    echo "Error: No upgrade URL found in fw_printenv"
    exit 1
fi

# ── Extract firmware filename ─────────────────────────
fw_file=$(basename "$fw_url")
local_url="http://10.5.0.1:81/$fw_file"

# ── Confirm and run upgrade ───────────────────────────
echo "Starting sysupgrade from: $local_url"
sysupgrade -k -r -n --url="$local_url"
