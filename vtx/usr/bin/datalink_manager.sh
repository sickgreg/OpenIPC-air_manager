#!/bin/sh
# Datalink Manager – list, info, auto-select, set

ADAPTER_CFG="/etc/wlan_adapters.yaml"
LINKMODES_CFG="/etc/link_modes.yaml"
WFB_CFG="/etc/wfb.yaml"
MAJESTIC_CFG="/etc/majestic.yaml"
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

preset_val() {
  yaml_str "$ADAPTER_CFG" ".profiles.$1.presets.$2.$3"
}

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
list_presets() {
  adapter=$(yaml_str "$WFB_CFG" ".wireless.wlan_adapter") || exit 1
  for p in $(yaml_list "$ADAPTER_CFG" ".profiles.$adapter.presets.all_presets"); do
    desc=$(preset_val "$adapter" "$p" description)
    vb=$(preset_val "$adapter" "$p" video_bitrate)
    printf "%-12s  %s  (video=%s kbps)\n" "$p" "$desc" "$vb"
  done
}



###############################################################################
set_mode() {
  mode="$2"
  [ -z "$mode" ] && { echo "Usage: $0 --set <mode_key>"; exit 1; }

  # Validate key exists in link_modes.yaml
  raw=$(yaml_num "$LINKMODES_CFG" ".link_modes.modes."$mode.raw_rate_mbps)
  [ -z "$raw" ] && { echo "Unknown mode '$mode'"; exit 1; }

  # Parse parts: mcs<num>_<bw>mhz_<lgi|sgi>
  IFS='_' read -r mcs_part bw_part gi_tag <<EOF
$mode
EOF
  mcs="${mcs_part#mcs}"             # strip "mcs"
  bandwidth="${bw_part%mhz}"        # strip "mhz"
  gi_full=$( [ "$gi_tag" = "lgi" ] && echo long || echo short )

  # Current STBC / LDPC from wfb.yaml (0/1)
  stbc=$(yaml_num "$WFB_CFG" ".broadcast.stbc"); [ -z "$stbc" ] && stbc=0
  ldpc=$(yaml_num "$WFB_CFG" ".broadcast.ldpc"); [ -z "$ldpc" ] && ldpc=0

  echo "Applying mode: $mode  (MCS=$mcs  BW=${bandwidth}MHz  GI=$gi_full  STBC=$stbc  LDPC=$ldpc)"

  # ── 1) Update width in /etc/wfb.yaml ───────────────────────────────────────
  yaml-cli -i "$WFB_CFG" -s .wireless.width "$bandwidth" >/dev/null \
    && echo "Updated wfb.yaml width → $bandwidth MHz"

  # ── 2) Re-set channel width with iw dev (assumes interface wlan0) ──────────
  channel=$(iw dev wlan0 info 2>/dev/null | awk '/channel/ {print $2}' | head -n1)
  if [ -n "$channel" ]; then
    if [ "$bandwidth" -eq 40 ]; then
      iw dev wlan0 set channel "$channel" HT40+ && echo "iw: set HT40+ on channel $channel"
    else
      iw dev wlan0 set channel "$channel" HT20   && echo "iw: set HT20  on channel $channel"
    fi
  else
    echo "Warning: could not determine current channel via 'iw dev'"
  fi

  # ── 3) Send set_radio to wfb_tx_cmd (port 8000) ────────────────────────────
  wfb_tx_cmd 8000 set_radio \
      -B "$bandwidth" \
      -G "$gi_full" \
      -S "$stbc" \
      -L "$ldpc" \
      -M "$mcs"

  echo "Radio configured via wfb_tx_cmd."

  # ── 4) Update gi,mcs in /etc/wfb.yaml ───────────────────────────────────────
  yaml-cli -i "$WFB_CFG" -s .broadcast.mcs_index "$mcs" >/dev/null \
    && echo "Updated wfb.yaml mcs_index → $mcs"
  yaml-cli -i "$WFB_CFG" -s .wireless.gi "$gi_full" >/dev/null \
    && echo "Updated wfb.yaml guard interval → $gi_full"
}

###############################################################################
set_preset() {
  adapter=$(yaml_str "$WFB_CFG" ".wireless.wlan_adapter") || exit 1
  preset="$2"
  [ -z "$preset" ] && { echo "Usage: $0 --set-preset <name>"; exit 1; }

  # Validate preset exists
  exists=$(yaml_raw "$ADAPTER_CFG" ".profiles.$adapter.presets.$preset" | grep -v '^\.')
  [ -z "$exists" ] && { echo "Preset '$preset' not found for $adapter"; exit 1; }

  # Extract fields
  vb=$(preset_val "$adapter" "$preset" video_bitrate)
  lm=$(preset_val "$adapter" "$preset" link_mode)
  fk=$(preset_val "$adapter" "$preset" fec_k)
  fn=$(preset_val "$adapter" "$preset" fec_n)
  ml=$(preset_val "$adapter" "$preset" mlink)
  fp=$(preset_val "$adapter" "$preset" fps)
  exp=$(preset_val "$adapter" "$preset" exposure)
 
  echo "Applying preset '$preset'  (link_mode=$lm  bitrate=$vb kbps  FEC=$fk/$fn  mlink=$ml)"

  # 1) Apply link mode (re-use existing --set)
  "$0" --set "$lm" || { echo "Failed to set link mode"; exit 1; }

  # 2) Update FEC and mlink in wfb.yaml
  yaml-cli -i "$WFB_CFG" -s .broadcast.fec_k "$fk"  >/dev/null
  yaml-cli -i "$WFB_CFG" -s .broadcast.fec_n "$fn"  >/dev/null
  yaml-cli -i "$WFB_CFG" -s .wireless.mlink  "$ml"  >/dev/null
  echo "Updated FEC (k=$fk n=$fn) and mlink=$ml"

  # 3) Tell video encoder to change bitrate
  #curl -s "http://localhost/api/v1/set?video0.bitrate=${vb}" >/dev/null \
  #  && echo "Video bitrate set to ${vb} kbps"

  # 4) Set permanent majestic settings.
  yaml-cli -i "$MAJESTIC_CFG" -s .video0.bitrate "$vb"  >/dev/null
  yaml-cli -i "$MAJESTIC_CFG" -s .video0.fps "$fp"  >/dev/null
  yaml-cli -i "$MAJESTIC_CFG" -s .video0.exposure "$exp"  >/dev/null
  echo "Updated bitrate ($vb) and fps=$fp and exposure=$exp"

  /etc/init.d/S95majestic restart
  sleep 1
  wifibroadcast start

  echo "Preset '$preset' applied."
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
  --list-modes)   list_modes ;;
  --list-presets) list_presets ;;
  --info)         info_adapter ;;
  --get-auto)     shift; get_auto "$@" ;;
  --set)          set_mode "$@" ;;
  --set-preset)   set_preset "$@" ;;
  --verbose)      VERBOSE=1; shift; "$0" "$@" ;;
  *)
    echo "Usage: $0 --list-modes | --list-presets | --info | --get-auto <kbps> [--verbose] | --set <mode> | --set-preset <name>"
    exit 1;;
esac
