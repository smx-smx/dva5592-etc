#!/bin/sh
AH_NAME="WiFiSSID"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$user" = "NoWiFi" ] && exit 0
[ "$user" = "$obj" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_wlan.sh
. /etc/ah/target.sh
wifi_set_bssid() {
local ifname="$1" bssid="$2"
case "$ifname" in
*.*|ath*)
if [ -n "$bssid" ]; then
echo "bss=$ifname" >> $ssidTempFile.$ifname
echo "bssid=$bssid" >> $ssidTempFile.$ifname
fi
;;
esac
}
wifi_set_bridge() {
local ifname="$1" _b _n _i_f _v_p _id
cmclient -v _b GETO "Device.Bridging.Bridge.Port.[LowerLayers=$obj].[X_ADB_FakePort!true].[Enable=true]"
cmclient -v _i_f GETV "$_b.IngressFiltering"
if [ "$_i_f" = "true" ]; then
cmclient -v _v_p GETO "Device.Bridging.Bridge.VLANPort.[Port=$_b].[Enable=true]"
cmclient -v _id GETV "%($_v_p.VLAN).[Enable=true].VLANID"
[ -n "$_id" ] && _id="_v$_id"
fi
cmclient -v _n GETV "${_b%.*}.[ManagementPort=true].Name"
if [ -n "$_n" ]; then
[ -n "$_id" ] && echo "bridge=$_n$_id" >> $ssidTempFile.$ifname || echo "bridge=$_n" >> $ssidTempFile.$ifname
fi
}
wifi_set_ssid() {
local ifname="$1" ssid="$2"
if [ -n "$ssid" ]; then
echo "ssid=$ssid" >> $ssidTempFile.$ifname
echo "auth_algs=1" >> $ssidTempFile.$ifname
fi
}
wifi_set_macmode() {
local ifname="$1" macmode="$2"
if [ -n "$macmode" ]; then
case $macmode in
"None" )
confVal="-1"
;;
"Deny" )
confVal="0"
;;
"Accept" )
confVal="1"
;;
* )
return
;;
esac
echo "macaddr_acl=$confVal" >> $ssidTempFile.$ifname
echo "accept_mac_file=/tmp/$ifname.accept" >> $ssidTempFile.$ifname
echo "deny_mac_file=/tmp/$ifname.deny" >> $ssidTempFile.$ifname
fi
}
service_get() {
local obj="$1" arg="$2"
case "$obj" in
*"Stats"*)
help_get_base_stats "$obj.$arg" "$ssid_ifname"
;;
esac
}
service_config() {
local ssid_name to_restart ap_obj radioName radioEnable intf
if [ "$changedSSID" = "1" ]; then
cmclient SET "Device.UserInterface.X_ADB_ProdPageAvailable" "false"
fi
if [ "$changedEnable" = "1" -a "$newEnable" = "false" ]; then
[ -e "$ssidTempFile.$newName" ] && rm -f $ssidTempFile.$newName
case "$newName" in
*.*|ath*)
wifi_set_bss_up "$newName" "Down"
wifi_set_bss_status "$obj" "Down"
;;
*)
cmclient -v ssid_name GET "Device.WiFi.SSID.[LowerLayers=$newLowerLayers].[Status!Down].Name"
for ssid_name in $ssid_name
do
wifi_set_bss_up "${ssid_name#*;}" "Down"
wifi_set_bss_status "${ssid_name%.Name*}" "Down"
done
;;
esac
cmclient SET "$obj.Stats.X_ADB_Reset" "true"
elif [ "$newEnable" = "true" ]; then
[ -e "$ssidTempFile.$newName" ] && rm -f $ssidTempFile.$newName
to_restart=0
if [ "$user" != "boot" ]; then
cmclient -v ap_obj GETO "Device.WiFi.AccessPoint.*.[SSIDReference=$obj].[Status=Enabled]"
for ap_obj in $ap_obj
do
cmclient -v radioName GETV "$newLowerLayers.Name"
[ ! -e "$apTempFile.$radioName" ] && cmclient -u boot SET "$ap_obj.Enable" "true"
wifi_stop "$radioName" "$newLowerLayers"
to_restart=1
break
done
fi
wifi_set_bssid "$newName" "$newBSSID"
wifi_set_bridge "$newName"
wifi_set_ssid "$newName" "$newSSID"
wifi_set_macmode "$newName" "$newX_ADB_MacMode"
wifi_set_bss_status "$obj" "Up"
if [ "$to_restart" -eq 1 ]; then
cmclient -v radioEnable GETV "$newLowerLayers.Enable"
wifi_config_start "$radioEnable" "$radioName" "$newLowerLayers"
fi
fi
if [ "$newX_ADB_Reset" = "true" ]; then
cmclient -v intf GETV ${obj%.*}.Name
wifiradio_reset_stats "$intf"
fi
}
case "$op" in
g)
case "$obj" in
*"Stats"*)
obj_path="${obj%.*}"
cmclient -v ssid_ifname GETV "$obj_path.Name"
;;
esac
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
;;
s)
service_config
;;
d)
[ -e "$ssidTempFile.$newName" ] && rm -f $ssidTempFile.$newName
case "$newName" in
*.*|ath*)
wifi_set_bss_up "$newName" "Down"
;;
*)
cmclient -v ssid_name GET "Device.WiFi.SSID.[LowerLayers=$newLowerLayers].[Status!Down].Name"
for ssid_name in $ssid_name
do
wifi_set_bss_up "${ssid_name#*;}" "Down"
wifi_set_bss_status "${ssid_name%.Name*}" "Down"
done
;;
esac
;;
esac
exit 0
