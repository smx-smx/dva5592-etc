#!/bin/sh
AH_NAME="WiFiBsd"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_functions.sh
. /etc/ah/helper_wifi_bsd.sh
. /etc/ah/helper_wlan.sh
. /etc/ah/target.sh
bsdConfTempFile="/tmp/wlan/bsdConf.tmp"
bsdConfVideoFile="/tmp/wlan/bsdConfVideo"
bsdConfBaseFile="/etc/wlan/bsd.conf"
bsdConf="/tmp/wlan/bsdConf"
bsdDualSta="/tmp/wlan/hostapd.dual.detect"
bsdDualDetectEnable="/tmp/wlan/bsdDualDetectEnable"
bsdDualDefined="/tmp/wlan/bsdDualBandDefined"
bsdSingleBandDefined="/tmp/wlan/bsdSingleBandDefined"
bsd_prepare_dual_band_defined() {
local dualband_stas=$1
set -f
IFS=","
set -- $dualband_stas
unset IFS
set +f
for arg; do
echo -n $arg" "
done > $bsdDualDefined
}
bsd_prepare_video_conf_file() {
local video_stas=$1
echo -n sta_config= > $bsdConfVideoFile
set -f
IFS=","
set -- $video_stas
unset IFS
set +f
for arg; do
echo -n $arg",2,1 "
done >> $bsdConfVideoFile
}
bsd_add_dual_band_config() {
local dualband_stas="$1"
[ ! -e $bsdConfTempFile ] && echo $bsdConfTempFile" does not exist">/dev/console && exit 0
set -f
IFS=","
set -- $dualband_stas
unset IFS
set +f
for arg; do
echo -n $arg",0,0 "
done >> $bsdConfTempFile
}
bsd_prepare_single_band_defined() {
local video_stas=$1 dualband_stas=$2
cmclient -v single_band_stas GETV Device.WiFi.X_ADB_BandSteering.SingleBandSTA
for def_sta in $single_band_stas; do
case ,$video_stas,$dualband_stas, in
*,"$def_sta",*)
;;
*)
echo -n "$def_sta "
;;
esac
done > $bsdSingleBandDefined
}
bsd_add_single_band_defined() {
local video_stas=$1 dualband_stas=$2
cmclient -v single_band_stas GETV Device.WiFi.X_ADB_BandSteering.SingleBandSTA
for def_sta in $single_band_stas; do
case ,$video_stas,$dualband_stas, in
*,"$def_sta",*)
;;
*)
echo -n $def_sta",0,1 "
;;
esac
done >> $bsdConfTempFile
}
bsd_prepare_assoc_not_defined() {
local video_stas=$1 dualband_stas=$2 all_assoc=""
cmclient -v all_assoc GETV Device.WiFi.AccessPoint.*.AssociatedDevice.*.MACAddress
for def_sta in $all_assoc; do
case ,$video_stas,$dualband_stas, in
*,"$def_sta",*)
;;
*)
echo -n $def_sta",0,1 "
;;
esac
done >> $bsdConfTempFile
}
bsd_prepare_conf_file() {
local all_assoc="" def_sta="" video_stas=$1 dualband_stas=$2 r24g_name=$3 r5g_name=$4 single_band_stas="" det_enabled="" rssi5ghz="" rssi24ghz="" \
deauth_time=""
[ ! -e "$bsdConfBaseFile" ] && echo BSD configuration base file not exists >> /dev/console && exit 0
bsd_prepare_dual_band_defined "$dualband_stas"
bsd_prepare_video_conf_file "$video_stas"
cp -f $bsdConfVideoFile $bsdConfTempFile
bsd_add_dual_band_config "$dualband_stas"
bsd_prepare_single_band_defined "$video_stas" "$dualband_stas"
bsd_add_single_band_defined "$video_stas" "$dualband_stas"
bsd_prepare_assoc_not_defined "$video_stas" "$dualband_stas"
echo ' ' >> $bsdConfTempFile
cmclient -v rssi5ghz GETV "Device.WiFi.X_ADB_BandSteering.RssiThreshold5"
cmclient -v rssi24ghz GETV "Device.WiFi.X_ADB_BandSteering.RssiThreshold24"
[ $rssi24ghz -lt 0 ] && echo "wl0_bsd_rssi_threshold="$rssi24ghz >> $bsdConfTempFile
[ $rssi5ghz -lt 0 ] && echo "wl1_bsd_rssi_threshold="$rssi5ghz >> $bsdConfTempFile
[ $rssi24ghz -eq 0 ] && echo "wl0_bsd_rssi_weight=0" >> $bsdConfTempFile
[ $rssi5ghz -eq 0 ] && echo "wl1_bsd_rssi_weight=0" >> $bsdConfTempFile
cmclient -v deauth_time GETV "Device.WiFi.X_ADB_BandSteering.DeauthTimeout"
[ $deauth_time -gt 0 ] && echo "bsd_deauth_timeout="$deauth_time >> $bsdConfTempFile
cat "$bsdConfBaseFile" "$bsdConfTempFile" > "$bsdConf"
sed -i "s/wl0/++/g; s/wl1/--/g; s/++/$r24g_name/g; s/--/$r5g_name/g" "$bsdConf"
cmclient -v det_enabled GETV Device.WiFi.X_ADB_BandSteering.DualBandDetectionEnable
[ "$det_enabled" = "true" ] && [ ! -e "$bsdDualDetectEnable" ] && touch "$bsdDualDetectEnable"
}
start_bsd_daemon() {
local i=0 j=0
while ! pidof bsd && [ $((i=i+1)) -le 3 ]; do
if [ $(pidof hostapd | wc -w) -ge 2 ]; then
help_svc_start "bsd" "bsd" 'daemon' '' '' '15' ''
while ! pidof bsd && [ $j -le 200 ]; do
sleep 0.1
j=$((j + 1))
done
fi
sleep 1
done
}
service_bsd_start_stop() {
local radio5g="" radio24g="" enabled_ssids_5g="" enabled_ssids_24g="" secmode5g="" secmode24g="" passwd5g="" passwd24g="" \
ssidref5g="" ssidref24g="" video_stas="" dualband_stas="" arg5g="" detect_enabled="" enabled="" r24g_name="" r5g_name=""
cmclient -v detect_enabled GETV Device.WiFi.X_ADB_BandSteering.DualBandDetectionEnable
if [ "$detect_enabled" = "true" ]; then
[ ! -e "$bsdDualDetectEnable" ] && touch "$bsdDualDetectEnable"
fi
cmclient -v radio5g GETO Device.WiFi.Radio.[OperatingFrequencyBand=5GHz].[Enable=true]
cmclient -v radio24g GETO Device.WiFi.Radio.[OperatingFrequencyBand=2.4GHz].[Enable=true]
case "$1" in
true)
if [ ${#radio5g} -eq 0 -o ${#radio24g} -eq 0 ]; then
cmclient SETE "Device.WiFi.X_ADB_BandSteering.Status" "Error_RadioOff"
exit 0
fi
cmclient SETE "Device.WiFi.X_ADB_BandSteering.Status" "Error_Misconfigured"
cmclient -v enabled_ssids_5g GETV Device.WiFi.SSID.[Enable=true].[LowerLayers=$radio5g].SSID
cmclient -v enabled_ssids_24g GETV Device.WiFi.SSID.[Enable=true].[LowerLayers=$radio24g].SSID
for arg5g in $enabled_ssids_5g; do
if help_is_in_list_general "$enabled_ssids_24g" "$arg5g"; then
cmclient -v ssidref5g GETO Device.WiFi.SSID.[LowerLayers=$radio5g].[SSID=$arg5g]
cmclient -v ssidref24g GETO Device.WiFi.SSID.[LowerLayers=$radio24g].[SSID=$arg5g]
cmclient -v secmode5g GETV Device.WiFi.AccessPoint.[SSIDReference=$ssidref5g].Security.ModeEnabled
cmclient -v secmode24g GETV Device.WiFi.AccessPoint.[SSIDReference=$ssidref24g].Security.ModeEnabled
cmclient -v passwd5g GETV Device.WiFi.AccessPoint.[SSIDReference=$ssidref5g].Security.KeyPassphrase
cmclient -v passwd24g GETV Device.WiFi.AccessPoint.[SSIDReference=$ssidref24g].Security.KeyPassphrase
cmclient -v video_stas GETV Device.WiFi.X_ADB_BandSteering.VideoSTA
cmclient -v dualband_stas GETV Device.WiFi.X_ADB_BandSteering.DualBandSTA
video_stas=$(help_lowercase $video_stas)
dualband_stas=$(help_lowercase $dualband_stas)
cmclient SETE Device.WiFi.X_ADB_BandSteering.DualBandSTA "$dualband_stas"
if [ "$secmode5g" = "$secmode24g" -a "$passwd5g" = "$passwd24g" ]; then
cmclient -v r24g_name GETV "$radio24g.Name"
cmclient -v r5g_name GETV "$radio5g.Name"
bsd_prepare_conf_file "$video_stas" "$dualband_stas" "$r24g_name" "$r5g_name"
if [ -e "$bsdConf" ]; then
start_bsd_daemon
if ! pidof bsd; then
cmclient SETE "Device.WiFi.X_ADB_BandSteering.Status" "Error"
else
cmclient SETE "Device.WiFi.X_ADB_BandSteering.Status" "Enabled"
fi
fi
fi
fi
done
;;
false)
help_svc_stop bsd "" 15
[ -e "$bsdConfTempFile" ] && rm "$bsdConfTempFile"
[ -e "$bsdConf" ] && rm "$bsdConf"
cmclient SETE "Device.WiFi.X_ADB_BandSteering.[Status!Error_RadioOff].Status" "Disabled"
;;
esac
}
start_stop_dualband_detection() {
local dualband_stas="" video_stas=""
case "$1" in
true)
if [ ! -e  "$bsdDualDetectEnable" ]; then
cmclient -v video_stas GETV Device.WiFi.X_ADB_BandSteering.VideoSTA
cmclient -v dualband_stas GETV Device.WiFi.X_ADB_BandSteering.DualBandSTA
[ ! -e "$bsdDualDefined" ] && bsd_prepare_dual_band_defined "$dualband_stas"
[ ! -e "$bsdConfVideoFile" ] && bsd_prepare_video_conf_file "$video_stas"
[ ! -e "$bsdSingleBandDefined" ] &&  bsd_prepare_single_band_defined "$video_stas" "$dualband_stas"
touch "$bsdDualDetectEnable"
fi
;;
false)
[ -e "$bsdDualDetectEnable" ] && rm "$bsdDualDetectEnable"
[ -e "$bsdDualDefined" ] && rm "$bsdDualDefined"
[ -e "$bsdSingleBandDefined" ] && rm "$bsdSingleBandDefined"
;;
esac
}
clear_bsd_sta_lists() {
cmclient SETE "Device.WiFi.X_ADB_BandSteering.VideoSTA" ""
cmclient SETE "Device.WiFi.X_ADB_BandSteering.SingleBandSTA" ""
cmclient SETE "Device.WiFi.X_ADB_BandSteering.DualBandSTA" ""
}
service_config() {
local airties_feature airties_enable bsd_start="false"
if [ "$setReset" = "1" -a "$newReset" = "true" ]; then
service_bsd_start_stop "false"
service_bsd_start_stop "true"
else
if [ "$setEnable" = "1" -o "$changedEnable" = "1" ]; then
service_bsd_start_stop "$newEnable"
fi
if [ "$oldDualBandDetectionEnable" = "true" ]; then
start_stop_dualband_detection "true"
fi
if [ "$changedDualBandDetectionEnable" = "1" ]; then
start_stop_dualband_detection "$newDualBandDetectionEnable"
fi
if [ "$setStatus" = "1" -a "$newStatus" = "Error_RadioOff" ]; then
service_bsd_start_stop "false"
fi
if [ "$setConfigReset" = "1" -a "$newConfigReset" = "true" ]; then
[ "$newEnable" = "true" -a "$newStatus" = "Enabled" ] && service_bsd_start_stop "false" && bsd_start="true"
clear_bsd_sta_lists
[ "$bsd_start" = "true" ] && service_bsd_start_stop "true"
fi
fi
help_store_host_which_uses_bsd
}
service_get() {
local dualband_stas=""
if [ -e "$bsdDualSta" ]; then
while read dualband_stas; do
:
done < $bsdDualSta
fi
echo $dualband_stas
}
case "$op" in
s)
service_config
;;
g)
service_get
;;
esac
exit 0
