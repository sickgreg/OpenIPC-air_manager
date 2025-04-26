#!/bin/sh

WFB_YAML="/etc/wfb.yaml"
WIFI_ADAPTERS_YAML="/etc/wifi_adapters.yaml"
WLAN_DEV="wlan0"

get_wifi_adapter() {
    yaml-cli -i "$WFB_YAML" -g .wireless.wifi_adapter
}

get_mcs_index() {
    wfb_tx_cmd 8000 get_radio | grep mcs_index | cut -d '=' -f2
}

get_radio_settings() {
    wfb_tx_cmd 8000 get_radio
}

get_tx_power_list() {
    yaml-cli -i "$WIFI_ADAPTERS_YAML" -g ".profiles.$1.tx_power.mcs$2" | tr -d '[]'
}

get_pwr_mw() {
    yaml-cli -i "$WIFI_ADAPTERS_YAML" -g ".profiles.$1.pwr_mw.$2"
}

is_valid_mcs() {
    case "$1" in
        0|1|2|3|4|5|6|7) return 0 ;;
        *) return 1 ;;
    esac
}

set_tx_power() {
    INDEX="$1"
    MCS_OVERRIDE="$2"

    if [ -z "$INDEX" ]; then
        echo "Usage: $0 set_tx_power <index 0-10> [--mcs <0-7>]"
        exit 1
    fi

    ADAPTER=$(get_wifi_adapter)
    if [ -z "$ADAPTER" ]; then
        echo "Error: Could not detect WiFi adapter."
        exit 1
    fi

    # If --mcs provided, use it for selecting tx_power list
    if [ -n "$MCS_OVERRIDE" ]; then
        if ! is_valid_mcs "$MCS_OVERRIDE"; then
            echo "Error: Invalid MCS value '$MCS_OVERRIDE'. Must be 0-7."
            exit 1
        fi
        TARGET_MCS="$MCS_OVERRIDE"
    else
        # Otherwise, use current MCS
        TARGET_MCS=$(get_mcs_index)
    fi

    TX_LIST=$(get_tx_power_list "$ADAPTER" "$TARGET_MCS")
    if [ -z "$TX_LIST" ]; then
        echo "Error: Could not find TX power list for adapter $ADAPTER MCS$TARGET_MCS."
        exit 1
    fi

    # Split TX_LIST manually
    COUNTER=0
    TX_POWER=""
    for VALUE in $(echo "$TX_LIST" | tr ',' ' ')
    do
        if [ "$COUNTER" -eq "$INDEX" ]; then
            TX_POWER="$VALUE"
            break
        fi
        COUNTER=$((COUNTER + 1))
    done

    if [ -z "$TX_POWER" ]; then
        echo "Error: Invalid index $INDEX for TX power list."
        exit 1
    fi

    # Get the mW value from YAML
    PWR_MW=$(get_pwr_mw "$ADAPTER" "$INDEX")

    echo "Setting TX power to ${TX_POWER} (index $INDEX) - expected ${PWR_MW}"
    iw dev "$WLAN_DEV" set txpower fixed "$TX_POWER"

    if [ $? -ne 0 ]; then
        echo "Failed to set TX power!"
        exit 1
    fi

    # Handle optional MCS override
    if [ -n "$MCS_OVERRIDE" ]; then
        echo "Changing MCS index to $MCS_OVERRIDE..."

        # Read current settings
        RADIO_SETTINGS=$(get_radio_settings)

        # Extract current parameters
        STBC=$(echo "$RADIO_SETTINGS" | grep "^stbc=" | cut -d '=' -f2)
        LDPC=$(echo "$RADIO_SETTINGS" | grep "^ldpc=" | cut -d '=' -f2)
        GI=$(echo "$RADIO_SETTINGS" | grep "^short_gi=" | cut -d '=' -f2)
        BW=$(echo "$RADIO_SETTINGS" | grep "^bandwidth=" | cut -d '=' -f2)

        # Issue the set_radio command
        wfb_tx_cmd 8000 set_radio -B "$BW" -G "$GI" -S "$STBC" -L "$LDPC" -M "$MCS_OVERRIDE"
        if [ $? -ne 0 ]; then
            echo "Failed to set new MCS index!"
            exit 1
        fi
    fi
}

# Entry point
if [ "$1" = "set_tx_power" ]; then
    if [ "$3" = "--mcs" ]; then
        set_tx_power "$2" "$4"
    else
        set_tx_power "$2"
    fi
else
    echo "Usage: $0 set_tx_power <index 0-10> [--mcs <0-7>]"
    exit 1
fi
