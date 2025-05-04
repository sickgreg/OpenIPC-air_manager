#!/bin/sh
set -o pipefail

case "$@" in
    "values air wfbng mcs_index")
        echo -n 0 10
        ;;
    "values air wfbng fec_k")
        echo -n 0 15
        ;;
    "values air wfbng fec_n")
        echo -n 0 15
        ;;
    "values air camera contrast")
        echo -n 0 100
        ;;
    "values air camera hue")
        echo -n 0 100
        ;;
    "values air camera saturation")
        echo -n 0 100
        ;;
    "values air camera luminace")
        echo -n 0 100
        ;;
    "values air camera gopsize")
        echo -n 0 10
        ;;
    "values air camera rec_split")
        echo -n 0 60
        ;;
    "values air camera rec_maxusage")
        echo -n 0 100
        ;;
    "values air camera exposure")
        echo -n 5 50
        ;;
    "values air camera noiselevel")
        echo -n 0 1
        ;;
    "values air telemetry osd_fps")
        echo -n 0 60
        ;;
    "values air wfbng power")
        echo -e "1\n20\n25\n30\n35\n40\n45\n50\n55\n58"
        ;;
    "values air wfbng air_channel")
        iw list | grep MHz | grep -v disabled | grep -v "radar detection" | grep \* | tr -d '[]' \
          | awk '{print $4 " (" $2 " " $3 ")"}' | grep '^[1-9]' | sort -n | uniq
        ;;
    "values air wfbng width")
        echo -e "20\n40"
        ;;
    "values air camera size")
        echo -e "1280x720\n1456x816\n1920x1080\n1440x1080\n1920x1440\n2104x1184\n2208x1248\n2240x1264\n2312x1304\n2436x1828\n2512x1416\n2560x1440\n2560x1920\n2720x1528\n2944x1656\n3200x1800\n3840x2160"
        ;;
    "values air camera fps")
        echo -e "60\n90\n120"
        ;;
    "values air camera bitrate")
        echo -e "1024\n2048\n3072\n4096\n5120\n6144\n7168\n8192\n9216\n10240\n11264\n12288\n13312\n14336\n15360\n16384\n17408\n18432\n19456\n20480\n21504\n22528\n23552\n24576\n25600\n26624\n27648\n28672\n29692\n30720"
        ;;
    "values air camera codec")
        echo -e "h264\nh265"
        ;;
    "values air camera rc_mode")
        echo -e "vbr\navbr\ncbr"
        ;;
    "values air camera antiflicker")
        echo -e "disabled\n50\n60"
        ;;
    "values air camera sensor_file")
        echo -e "/etc/sensors/imx307.bin\n/etc/sensors/imx335.bin\n/etc/sensors/imx335_fpv.bin\n/etc/sensors/imx415_fpv.bin\n/etc/sensors/imx415_fpv.bin\n/etc/sensors/imx415_milos10.bin\n/etc/sensors/imx415_milos15.bin\n/etc/sensors/imx335_milos12tweak.bin\n/etc/sensors/imx335_greg15.bin\n/etc/sensors/imx335_spike5.bin\n/etc/sensors/gregspike05.bin"
        ;;
    "values air telemetry serial")
        echo -e "ttyS0\nttyS1\nttyS2"
        ;;
    "values air telemetry router")
        echo -e "mavfwd\nmsposd"
        ;;

    "get air camera mirror")
        [ "true" = "$(cli -g .image.mirror)" ] && echo 1 || echo 0
        ;;
    "get air camera flip")
        [ "true" = "$(cli -g .image.flip)" ] && echo 1 || echo 0
        ;;
    "get air camera contrast")
        cli -g .image.contrast
        ;;
    "get air camera hue")
        cli -g .image.hue
        ;;
    "get air camera saturation")
        cli -g .image.saturation
        ;;
    "get air camera luminace")
        cli -g .image.luminance
        ;;
    "get air camera size")
        cli -g .video0.size
        ;;
    "get air camera fps")
        cli -g .video0.fps
        ;;
    "get air camera bitrate")
        cli -g .video0.bitrate
        ;;
    "get air camera codec")
        cli -g .video0.codec
        ;;
    "get air camera gopsize")
        cli -g .video0.gopSize
        ;;
    "get air camera rc_mode")
        cli -g .video0.rcMode
        ;;
    "get air camera rec_enable")
        [ "true" = "$(cli -g .records.enabled)" ] && echo 1 || echo 0
        ;;
    "get air camera rec_split")
        cli -g .records.split
        ;;
    "get air camera rec_maxusage")
        cli -g .records.maxUsage
        ;;
    "get air camera exposure")
        cli -g .isp.exposure
        ;;
    "get air camera antiflicker")
        cli -g .isp.antiFlicker
        ;;
    "get air camera sensor_file")
        cli -g .isp.sensorConfig
        ;;
    "get air camera fpv_enable")
        cli -g .fpv.enabled | grep -q true && echo 1 || echo 0
        ;;
    "get air camera noiselevel")
        cli -g .fpv.noiseLevel
        ;;

    "set air camera mirror"*)
        if [ "$5" = "on" ]; then
            cli -s .image.mirror true && killall -1 majestic
        else
            cli -s .image.mirror false && killall -1 majestic
        fi
        ;;
    "set air camera flip"*)
        if [ "$5" = "on" ]; then
            cli -s .image.flip true && killall -1 majestic
        else
            cli -s .image.flip false && killall -1 majestic
        fi
        ;;
    "set air camera contrast"*)
        cli -s .image.contrast "$5" && killall -1 majestic
        ;;
    "set air camera hue"*)
        cli -s .image.hue "$5" && killall -1 majestic
        ;;
    "set air camera saturation"*)
        cli -s .image.saturation "$5" && killall -1 majestic
        ;;
    "set air camera luminace"*)
        cli -s .image.luminance "$5" && killall -1 majestic
        ;;
    "set air camera size"*)
        cli -s .video0.size "$5" && killall -1 majestic
        ;;
    "set air camera fps"*)
        cli -s .video0.fps "$5" && killall -1 majestic
        ;;
    "set air camera bitrate"*)
        cli -s .video0.bitrate "$5" && killall -1 majestic
        ;;
    "set air camera codec"*)
        cli -s .video0.codec "$5" && killall -1 majestic
        ;;
    "set air camera gopsize"*)
        cli -s .video0.gopSize "$5" && killall -1 majestic
        ;;
    "set air camera rc_mode"*)
        cli -s .video0.rcMode "$5" && killall -1 majestic
        ;;
    "set air camera rec_enable"*)
        if [ "$5" = "on" ]; then
            cli -s .records.enable true && killall -1 majestic
        else
            cli -s .records.enable false && killall -1 majestic
        fi
        ;;
    "set air camera rec_split"*)
        cli -s .records.split "$5" && killall -1 majestic
        ;;
    "set air camera rec_maxusage"*)
        cli -s .records.maxUsage "$5" && killall -1 majestic
        ;;
    "set air camera exposure"*)
        cli -s .isp.exposure "$5" && killall -1 majestic
        ;;
    "set air camera antiflicker"*)
        cli -s .isp.antiFlicker "$5" && killall -1 majestic
        ;;
    "set air camera sensor_file"*)
        cli -s .isp.sensorConfig "$5" && killall -1 majestic
        ;;
    "set air camera fpv_enable"*)
        if [ "$5" = "on" ]; then
            cli -s .fpv.enabled true && killall -1 majestic
        else
            cli -s .fpv.enabled false && killall -1 majestic
        fi
        ;;
    "set air camera noiselevel"*)
        cli -s .fpv.noiseLevel "$5" && killall -1 majestic
        ;;

    "get air telemetry serial")
        wifibroadcast cli -g .telemetry.serial
        ;;
    "get air telemetry router")
        wifibroadcast cli -g .telemetry.router
        ;;
    "get air telemetry osd_fps")
        wifibroadcast cli -g .telemetry.osd_fps
        ;;
    "get air telemetry gs_rendering")
        grep "\-z \"\$size\"" /usr/bin/wifibroadcast | grep -q size && echo 0 || echo 1
        ;;

    "set air telemetry serial"*)
        wifibroadcast cli -s .telemetry.serial "$5"
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air telemetry router"*)
        wifibroadcast cli -s .telemetry.router "$5"
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air telemetry osd_fps"*)
        wifibroadcast cli -s .telemetry.osd_fps "$5"
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air telemetry gs_rendering"*)
        if [ "$5" = "on" ]; then
            sed -i 's/-o 127\.0\.0\.1:\"\$port_tx\" -z \"\$size\"/-o 10\.5\.0\.1:\"\$port_tx\"/' /usr/bin/wifibroadcast
        else
            sed -i 's/-o 10\.5\.0\.1:\"\$port_tx\"/-o 127\.0\.0\.1:\"\$port_tx\" -z \"\$size\"/' /usr/bin/wifibroadcast
        fi
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;

    "get air wfbng power")
        wifibroadcast cli -g .wireless.txpower
        ;;
    "get air wfbng air_channel")
        channel=$(wifibroadcast cli -g .wireless.channel | tr -d '\n')
        iw list | grep "\[$channel\]" | tr -d '[]' | awk '{print $4 " (" $2 " " $3 ")"}' | sort -n | uniq | tr -d '\n'
        ;;
    "get air wfbng width")
        wifibroadcast cli -g .wireless.width
        ;;
    "get air wfbng mcs_index")
        wifibroadcast cli -g .broadcast.mcs_index
        ;;
    "get air wfbng stbc")
        wifibroadcast cli -g .broadcast.stbc
        ;;
    "get air wfbng ldpc")
        wifibroadcast cli -g .broadcast.ldpc
        ;;
    "get air wfbng fec_k")
        wifibroadcast cli -g .broadcast.fec_k
        ;;
    "get air wfbng fec_n")
        wifibroadcast cli -g .broadcast.fec_n
        ;;
    "get air wfbng adaptivelink")
        grep ^alink_drone /etc/rc.local | grep -q 'alink_drone' && echo 1 || echo 0
        ;;

    "set air wfbng power"*)
        wifibroadcast cli -s .wireless.txpower "$5"
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air wfbng air_channel"*)
        channel=$(echo "$5" | awk '{print $1}')
        wifibroadcast cli -s .wireless.channel "$channel"
        (wifibroadcast stop; sleep 1; wifibroadcast start) >/dev/null 2>&1 &
        sed -i "s/^wifi_channel =.*/wifi_channel = $channel/" /etc/wifibroadcast.cfg
        systemctl restart wifibroadcast.service
        ;;
    "set air wfbng width"*)
        wifibroadcast cli -s .wireless.width "$5"
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air wfbng mcs_index"*)
        wifibroadcast cli -s .broadcast.mcs_index "$5"
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air wfbng stbc"*)
        if [ "$5" = "on" ]; then
            wifibroadcast cli -s .broadcast.stbc 1
        else
            wifibroadcast cli -s .broadcast.stbc 0
        fi
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air wfbng ldpc"*)
        if [ "$5" = "on" ]; then
            wifibroadcast cli -s .broadcast.ldpc 1
        else
            wifibroadcast cli -s .broadcast.ldpc 0
        fi
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air wfbng fec_k"*)
        wifibroadcast cli -s .broadcast.fec_k "$5"
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air wfbng fec_n"*)
        wifibroadcast cli -s .broadcast.fec_n "$5"
        (wifibroadcast stop; wifibroadcast start) >/dev/null 2>&1 &
        ;;
    "set air wfbng adaptivelink"*)
        if [ "$5" = "on" ]; then
            sed -i "/alink_drone &/d" /etc/rc.local
            sed -i -e "\$i alink_drone &" /etc/rc.local
            cli -s .video0.qpDelta -12 && killall -1 majestic
            nohup alink_drone >/dev/null 2>&1 &
        else
            killall -q -9 alink_drone
            sed -i "/alink_drone &/d" /etc/rc.local
            cli -d .video0.qpDelta && killall -1 majestic
        fi
        ;;
    *)
        echo "Unknown $@"
        exit 1
        ;;
esac

case $? in
    0) ;;
    1) exit 0 ;;
    *) exit $? ;;
esac
