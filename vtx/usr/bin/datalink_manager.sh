#!/bin/sh
# Datalink Manager – list, info, auto-select, set

ADAPTER_CFG="/etc/wlan_adapters.yaml"
LINKMODES_CFG="/etc/link_modes.yaml"
WFB_CFG="/etc/wfb.yaml"
VERBOSE=0

###############################################################################
# YAML helpers (always use -g for query)
###############################################################################
yaml_raw()  { yaml-cli -i "$1" -g "$2" 2>/dev/null; }

yaml_num()  { yaml_raw "$1" "$2" | grep -Eo '[0-9.]+' | head -n1; }
yaml_str()  { yaml_raw "$1" "$2" | tail -n1; }
yaml_list() {
  yaml_raw "$1" "$2" \
    | tr -d '[]' \
    | tr ',' '\n' \
    | tr -d ' ' \
    | grep -v '^$'
}

bw_group()  { printf "%smhz" "$1"; }

raw_rate()  { yaml_num "$LINKMODES_CFG" ".link_modes.modes.$1.raw_rate_mbps"; }
net30() { r=$(raw_rate "$1"); [ -z "$r" ] && echo 0 || printf "scale=4; $r*0.70\n" | bc -l; }
mtu()  { yaml_num "$LINKMODES_CFG" ".link_modes.modes.$1.mtu_recommendation"; }

dbg() { [ "$VERBOSE" -eq 1 ] && echo "DEBUG: $*"; }

###############################################################################
list_modes() {
  adapter=$(yaml_str "$WFB_CFG" ".wireless.wlan_adapter") || exit 1
  for bw in 10mhz 20mhz 40mhz; do
    echo "=== $bw ==="
    for key in $(yaml_list "$ADAPTER_CFG" ".profiles.$adapter.link_modes.$bw"); do
      printf "  %-18s ~%6.1f Mbps  MTU:%4s\n" "$key" "$(net30 "$key")" "$(mtu "$key")"
    done
  done
}

###############################################################################
info_adapter() {
  # ── active adapter name ────────────────────────────────────────────────────
  a=$(yaml_str "$WFB_CFG" ".wireless.wlan_adapter") || exit 1

  # ── adapter capabilities (from wlan_adapters.yaml) ─────────────────────────
  bw=$(yaml_list "$ADAPTER_CFG" ".profiles.$a.bw"       | paste -sd ',' -)
  gi=$(yaml_list "$ADAPTER_CFG" ".profiles.$a.guard"    | paste -sd ',' -)
  mcs_list=$(yaml_list "$ADAPTER_CFG" ".profiles.$a.mcs"| paste -sd ',' -)
  mcs_min=$(echo "$mcs_list" | cut -d',' -f1)
  mcs_max=$(echo "$mcs_list" | awk -F',' '{print $NF}')
  mcs_count=$(echo "$mcs_list" | tr ',' '\n' | wc -l)
  if [ "$mcs_count" -eq $((mcs_max - mcs_min + 1)) ]; then
    mcs="${mcs_min}-${mcs_max}"
  else
    mcs="$mcs_list"
  fi
  mtu=$(yaml_num "$ADAPTER_CFG" ".profiles.$a.max_mtu")
  lm10=$(yaml_list "$ADAPTER_CFG" ".profiles.$a.link_modes.10mhz" | paste -sd ',' -)
  lm20=$(yaml_list "$ADAPTER_CFG" ".profiles.$a.link_modes.20mhz" | paste -sd ',' -)
  lm40=$(yaml_list "$ADAPTER_CFG" ".profiles.$a.link_modes.40mhz" | paste -sd ',' -)

  echo "adapter=$a;bw=$bw;guard=$gi;mcs=$mcs;max_mtu=$mtu;link_modes_10=$lm10;link_modes_20=$lm20;link_modes_40=$lm40"

  # ── live settings from wfb.yaml (wireless & broadcast sections) ────────────
  width=$(yaml_num "$WFB_CFG" ".wireless.width")
  chan=$(yaml_num "$WFB_CFG" ".wireless.channel")
  txp=$(yaml_num "$WFB_CFG" ".wireless.txpower")
  mlink=$(yaml_num "$WFB_CFG" ".wireless.mlink")
  lctl=$(yaml_str "$WFB_CFG" ".wireless.link_control")
  fec_k=$(yaml_num "$WFB_CFG" ".broadcast.fec_k")
  fec_n=$(yaml_num "$WFB_CFG" ".broadcast.fec_n")
  stbc=$(yaml_num "$WFB_CFG" ".broadcast.stbc")
  ldpc=$(yaml_num "$WFB_CFG" ".broadcast.ldpc")

  echo "wfb=width=$width;channel=$chan;txpower=$txp;mlink=$mlink;link_control=$lctl;fec_k=$fec_k;fec_n=$fec_n;stbc=$stbc;ldpc=$ldpc"
}


###############################################################################
set_mode() {
  [ -z "$2" ] && { echo "Usage: $0 --set <mode>"; exit 1; }
  yaml-cli -i "$WFB_CFG" -g ".wireless.linkmode" -s "$2" &&
  echo "Saved mode '$2' (TODO: apply driver settings)"
}

###############################################################################
get_auto() {
  [ -z "$1" ] && { echo "Usage: $0 --get-auto <kbps> [--verbose]"; exit 1; }
  need_kbps="$1"; shift
  [ "$1" = "--verbose" ] && { VERBOSE=1; shift; }

  fec_n=$(yaml_num "$WFB_CFG" ".broadcast.fec_n"); [ -z "$fec_n" ] && fec_n=1
  fec_k=$(yaml_num "$WFB_CFG" ".broadcast.fec_k"); [ -z "$fec_k" ] && fec_k=1
  width=$(yaml_num "$WFB_CFG" ".wireless.width");  [ -z "$width" ] && width=20
  group=$(bw_group "$width")
  adapter=$(yaml_str "$WFB_CFG" ".wireless.wlan_adapter")

  required=$(printf "scale=4; %s * %s / %s / 1024\n" "$need_kbps" "$fec_n" "$fec_k" | bc -l)
  dbg "need_kbps=$need_kbps  FEC=$fec_k/$fec_n  width=$width($group)  required=$required Mbps"

  for key in $(yaml_list "$ADAPTER_CFG" ".profiles.$adapter.link_modes.$group"); do
    rate=$(net30 "$key"); raw=$(raw_rate "$key")
    dbg "  key=$key  raw=$raw  net30=$rate"
    if printf "%s >= %s\n" "$rate" "$required" | bc -l | grep -q 1; then
      printf "%s (net30≈%.1f Mbps, MTU:%s)\n" "$key" "$rate" "$(mtu "$key")"
      return
    fi
  done
  echo "No mode fits ${need_kbps} kbps in $group with FEC $fec_k/$fec_n."
}

###############################################################################
case "$1" in
  --list-modes) list_modes ;;
  --info)       info_adapter ;;
  --get-auto)   shift; get_auto "$@" ;;
  --set)        set_mode "$@" ;;
  --verbose)    VERBOSE=1; shift; "$0" "$@" ;;
  *)
    echo "Usage: $0 --list-modes | --info | --get-auto <kbps> [--verbose] | --set <mode>"
    exit 1;;
esac
