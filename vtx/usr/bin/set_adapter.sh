#!/bin/sh
#
# set_adapter.sh  – pick a wireless-adapter profile by name or list index
# Usage examples:
#   set_adapter.sh            # show numbered list only
#   set_adapter.sh bl-r8812af1
#   set_adapter.sh 2

YAML=yaml-cli
PROFILES_FILE=/etc/wlan_adapters.yaml
TARGET_FILE=/etc/wfb.yaml

die() { printf '%s\n' "$*" >&2; exit 1; }

# Grab raw “[a,b,c]” output
raw="$("$YAML" -i "$PROFILES_FILE" -g .all_profiles. 2>/dev/null)" \
  || die "Failed to read profiles from $PROFILES_FILE"

# Remove brackets, turn commas → spaces  ⇐  **fixed line**
profiles=$(printf '%s\n' "$raw" | tr -d '[]' | tr ',' ' ')
#              └───────── keep ▢       └───── replace with spaces

# Save optional user argument, then overwrite $@ with the profile list
user_sel=$1
shift 2>/dev/null || true
set -- $profiles                       # $1…$# are now the adapters
[ "$#" -gt 0 ] || die "No adapter profiles found."

show_list() {
  i=1; for p; do
    printf '%d. %s\n' "$i" "$p"
    i=$((i+1))
  done
}

# No argument → just print menu
[ -n "$user_sel" ] || { show_list "$@"; exit 0; }

# Resolve name vs. index
case $user_sel in
  ''|*[!0-9]*) adapter=$user_sel ;;    # looks like a name
  *)  idx=$user_sel
      [ "$idx" -ge 1 ] && [ "$idx" -le "$#" ] \
        || die "Index $idx out of range (1-$#)."
      adapter=$(eval "echo \${$idx}") ;;
esac

# Verify existence
for p; do [ "$p" = "$adapter" ] && found=1 && break; done
[ "$found" ] || { printf 'Error: adapter "%s" not found.\n\n' "$adapter" >&2
                  show_list "$@"; exit 1; }

# Apply
if "$YAML" -i "$TARGET_FILE" -s .wireless.wlan_adapter "$adapter"; then
  printf 'Adapter "%s" successfully set. Restarting wifibroadcast.\n' "$adapter"
  wifibroadcast start
else
  die "Failed to set adapter \"$adapter\"."
fi


