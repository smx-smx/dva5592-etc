#!/bin/sh
AH_NAME="WiFiAssocDevice"
. /etc/ah/helper_serialize.sh && help_serialize "$AH_NAME" >/dev/null
. /etc/ah/target.sh
service_get() {
local obj="$1" arg="$2" rateset_min=${wifi_assoc_rateset#* } buf= rx_pkts_tot= rx_bytes= tx_bytes=
rateset_min=${rateset_min%% *}
if [ "$rateset_min" = "5.5" ]; then
rateset_min=5500
else
rateset_min=$((rateset_min*1000))
fi
case "$arg" in
"X_ADB_Protocol" ) echo "$wifi_assoc_mode" ;;
"LastDataDownlinkRate" )
if [ "$wifi_assoc_downlink_rate" = "-1" ]; then
echo "$rateset_min"
else
echo "$wifi_assoc_downlink_rate"
fi
;;
"LastDataUplinkRate" )
if [ "$wifi_assoc_uplink_rate" = "-1" ]; then
echo "$rateset_min"
else
echo "$wifi_assoc_uplink_rate"
fi
;;
"PacketsSent" ) echo "$wifi_assoc_tx_pkts" ;;
"PacketsReceived" ) echo "$wifi_assoc_rx_pkts" ;;
"BytesSent" ) echo "$wifi_assoc_tx_bytes" ;;
"BytesReceived" ) echo "$wifi_assoc_rx_bytes" ;;
"ErrorsSent" ) echo "$wifi_assoc_tx_failures" ;;
"SignalStrength" ) echo "$wifi_assoc_rx_rssi" ;;
"X_ADB_Throughput" ) echo "$wifi_assoc_throughput" ;;
"X_ADB_Quality")
wifi_assoc_lq="Excellent"
[ $wifi_assoc_rx_rssi -lt -35 ] && wifi_assoc_lq="Good"
[ $wifi_assoc_rx_rssi -lt -55 ] && wifi_assoc_lq="Medium"
[ $wifi_assoc_rx_rssi -lt -75 ] && wifi_assoc_lq="Poor"
echo $wifi_assoc_lq ;;
"X_ADB_AssociationTime" )
wifi_assoc_time=$((`date +%s`-wifi_assoc_time))
echo `date --date @$wifi_assoc_time -u +%FT%TZ`
;;
*) echo "" ;;
esac
}
case "$op" in
g)
case "$obj" in
*"Stats"*)
obj_parent="${obj%.*}"
cmclient -v mac GETV "$obj_parent.MACAddress"
cmclient -v ssidname GETV "%(${obj_parent%.AssociatedDevice*}.SSIDReference).Name"
;;
*"AssociatedDevice"*)
cmclient -v mac GETV "$obj.MACAddress"
cmclient -v ssidname GETV "%(${obj%.AssociatedDevice*}.SSIDReference).Name"
;;
esac
[ -z "$mac" -o -z "$ssidname" ] && exit 0
wifiradio_get_assoc_stats "$mac" "$ssidname"
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
;;
esac
exit 0
