#!/bin/sh
AH_NAME="WiFiAP"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "NoWiFi" ] && exit 0
[ "$user" = "$obj" ] && exit 0
[ "$user" = "${obj}.Security" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_functions.sh
. /etc/ah/helper_wlan.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/WiFiSecurity.sh
. /etc/ah/WiFiWPS.sh
. /etc/ah/target.sh
wifi_segregate() {
local w_iface="$1" segregation="$2" ssidObj="$3" board_mac="" \
mac_mask="FF:FF:FF:FF:FF:00" operations="D" gui_iface curr_gi \
cmd ip_addresses cur_ip
cmclient -v gui_iface GETV Device.UserInterface.X_ADB_LocalAccess.Interface
[ -z "$gui_iface" ] && cmclient -v gui_iface GETO Device.IP.Interface.+.[X_ADB_Upstream=false]
cmclient -v board_mac GETV Device.X_ADB_FactoryData.BaseMACAddress
[ "$segregation" = "true" ] && operations="${operations} A"
for cmd in $operations; do
ebtables -t nat "-${cmd}" WiFiSegregation -i "$w_iface" -d Broadcast -j ACCEPT
ebtables -t nat "-${cmd}" WiFiSegregation -i "$w_iface" -d "$board_mac"/"$mac_mask" -j ACCEPT
ebtables -t nat "-${cmd}" WiFiSegregation -i "$w_iface" -j DROP
done
}
wifi_get_operating_standard() {
local ssid="" lstd="" mode=0
cmclient -v ssid GETV $2.SSIDReference
cmclient -v lstd GETV "%($ssid.LowerLayers).OperatingStandards"
case ",$lstd," in
*,a,*|*,b,*) mode=0 ;;
*,g,*) mode=1 ;;
*,n,*) mode=2 ;;
*,ac,*) mode=3 ;;
esac
eval $1='$mode'
return 0
}
wifi_ap_reconf() {
local ssid_ifname="$1" std="" lobj=$2
{
if [ -n "$wifi_ssid_adv" ]; then
if [ "$wifi_ssid_adv" = "true" ]; then
echo "ignore_broadcast_ssid=0"
else
echo "ignore_broadcast_ssid=1"
fi
fi
if [ -n "$wifi_assoc_limit" ]; then
echo "max_num_sta=$wifi_assoc_limit"
fi
if [ -n "$wifi_short_retry" ]; then
wifiradio_set_retry short $wifi_short_retry
fi
if [ -n "$wifi_long_retry" ]; then
wifiradio_set_retry long $wifi_long_retry
fi
if [ -n "$wifi_wmm_bss" ]; then
if [ "$wifi_wmm_bss" = "true" ]; then
wifiradio_set_wmm_bss enable
else
wifiradio_set_wmm_bss disable
fi
fi
if [ -n "$wifi_wmf" ]; then
if [ "$wifi_wmf" = "true" ]; then
echo "wmf=1"
else
echo "wmf=0"
fi
fi
if [ -n "$wifi_ap_isolation" ]; then
if [ "$wifi_ap_isolation" = "true" ]; then
echo "ap_isolation=1"
else
echo "ap_isolation=0"
fi
fi
if [ -n "$wifi_uapsd" ]; then
if [ "$wifi_uapsd" = "true" -a "${wifi_wmm_bss:-false}" = "true" ]; then
echo "uapsd_advertisement_enabled=1"
else
echo "uapsd_advertisement_enabled=0"
fi
fi
echo 'ap_max_inactivity=60'
wifi_get_operating_standard 'std' $lobj
echo "mode_reqd=$std"
} >> $apTempFile.$ssid_ifname
}
service_reconf_ap() {
local _enable="$1"
local _status="$2"
local _path="$3"
new_status="$_status"
service_read_ap $_path
if [ "$_enable" = "true" ]; then
if [ -z "$wifi_ssid_ifname" ]; then
new_status="Error_Misconfigured"
else
if [ "$wifi_ssid_enable" = "true" -a "$user" != "boot" -a "$user" != "notstart" ]; then
cmclient -v radioObj GETV "$wifi_ssid_ref.LowerLayers"
cmclient -v radioName GETV "$radioObj.Name"
wifi_stop "$radioName" "$radioObj"
fi
wifi_ap_reconf "$wifi_ssid_ifname" $_path
service_config_ap_security "" "$_path" "$wifi_ssid_ifname"
service_config_ap_wps "" "$_path" "$wifi_ssid_ifname"
new_status="Enabled"
[ "$newX_ADB_WirelessSegregation" = "true" ] && wifi_segregate "$wifi_ssid_ifname" "true" "$wifi_ssid_ref"
if [ "$wifi_ssid_enable" = "true" -a "$user" != "boot" -a "$user" != "notstart" ]; then
cmclient -v radioEnable GETV "$radioObj.Enable"
wifi_config_start "$radioEnable" "$radioName" "$radioObj"
fi
fi
else
new_status="Disabled"
fi
if [ "$new_status" != "$_status" ]; then
echo "### $AH_NAME: SET <$_path.Status> <$new_status> ###"
cmclient -u "${AH_NAME}${_path}" SET "$_path.Status" "$new_status"
fi
}
service_read_ap() {
local ap_obj="$1"
if [ -n "$ap_obj" ]; then
cmclient -v wifi_ssid_ref GETV "$ap_obj.SSIDReference"
cmclient -v wifi_ssid_adv GETV "$ap_obj.SSIDAdvertisementEnabled"
cmclient -v wifi_assoc_limit GETV "$ap_obj.X_ADB_MaxAssocLimit"
cmclient -v wifi_short_retry GETV "$ap_obj.RetryLimit"
cmclient -v wifi_long_retry GETV "$ap_obj.X_ADB_LongRetryLimit"
cmclient -v wifi_wmm_bss GETV "$ap_obj.WMMEnable"
cmclient -v wifi_uapsd GETV "$ap_obj.UAPSDEnable"
cmclient -v wifi_wmf GETV "$ap_obj.X_ADB_MulticastToUnicastEnable"
cmclient -v wifi_ap_isolation GETV "$ap_obj.X_ADB_APIsolation"
else
wifi_ssid_ref="$newSSIDReference"
wifi_ssid_adv="$newSSIDAdvertisementEnabled"
wifi_assoc_limit="$newX_ADB_MaxAssocLimit"
wifi_short_retry="$newRetryLimit"
wifi_long_retry="$newX_ADB_LongRetryLimit"
wifi_wmm_bss="$newWMMEnable"
wifi_uapsd="$newUAPSDEnable"
wifi_wmf="$newX_ADB_MulticastToUnicastEnable"
wifi_ap_isolation="$newX_ADB_APIsolation"
fi
cmclient -v wifi_ssid_enable GETV "$wifi_ssid_ref.Enable"
cmclient -v wifi_ssid_ifname GETV "$wifi_ssid_ref.Name"
[ -e "$apTempFile.$wifi_ssid_ifname" ] && rm -f $apTempFile.$wifi_ssid_ifname
}
service_reconf_security_wps() {
local sub_obj="$1"
ap_object="${obj%%.$sub_obj*}"
cmclient -v ap_enabled GETV "$ap_object.Enable"
if [ "$ap_enabled" = "true" ]; then
if [ "$sub_obj" = "WPS" -a "$newEnable" = "false" ]; then
if [ "$changedEnable" -eq 0 ]; then
return
fi
fi
service_read_ap "$ap_object"
if [ "$wifi_ssid_enable" = "true" ]; then
cmclient -v radioObj GETV "$wifi_ssid_ref.LowerLayers"
cmclient -v radioName GETV "$radioObj.Name"
if [ "$user" != "notstart" ]; then
wifi_stop "$radioName" "$radioObj"
fi
fi
wifi_ap_reconf "$wifi_ssid_ifname" $ap_object
if [ "$sub_obj" = "WPS" ]; then
service_config_ap_security "" "$ap_object" "$wifi_ssid_ifname"
service_config_ap_wps "$obj" "$ap_object" "$wifi_ssid_ifname"
elif [ "$sub_obj" = "Security" ]; then
service_config_ap_security "$obj" "$ap_object" "$wifi_ssid_ifname"
service_config_ap_wps "" "$ap_object" "$wifi_ssid_ifname"
elif [ "$sub_obj" = "Accounting" ]; then
service_config_ap_security "" "$ap_object" "$wifi_ssid_ifname" "$obj"
service_config_ap_wps "" "$ap_object" "$wifi_ssid_ifname"
fi
if [ "$wifi_ssid_enable" = "true" -a "$user" != "notstart" ]; then
cmclient -v radioEnable GETV "$radioObj.Enable"
wifi_config_start "$radioEnable" "$radioName" "$radioObj"
fi
elif [ "$sub_obj" = "Security" ]; then
{ [ ${setKeyPassphrase:-0} -eq 1 ] && cmclient SETE "$ap_object.Security.PreSharedKey" ""; } \
|| { [ ${setPreSharedKey:-0} -eq 1 ] && cmclient SETE "$ap_object.Security.KeyPassphrase" ""; }
fi
}
service_config() {
if [ "$changedKeyPassphrase" = "1" -o "$changedWEPKey" = "1" ]; then
cmclient SET "Device.UserInterface.X_ADB_ProdPageAvailable" "false"
fi
case "$obj" in
*"Radio"*)
if [ $changedOperatingStandards -eq 1 ]; then
user="notstart"
cmclient -v ssid_path GETO "Device.WiFi.SSID.[LowerLayers=$obj].[Enable=true]"
for ssid_path in $ssid_path; do
cmclient -v ap_path GETO "Device.WiFi.AccessPoint.[SSIDReference=$ssid_path].[Enable=true]"
for ap_path in $ap_path; do
cmclient -v newStatus GETV $ap_path.Status
service_reconf_ap "true" "$newStatus" "$ap_path"
done
done
fi
;;
*"Security"*)
service_reconf_security_wps "Security"
;;
*"WPS"*)
service_reconf_security_wps "WPS"
;;
*"Accounting"*)
service_reconf_security_wps "Accounting"
;;
*)
if [ "$changedX_ADB_WirelessSegregation" -eq 1 ]; then
local w_iface
cmclient -v w_iface GETV "$newSSIDReference.Name"
wifi_segregate "$w_iface" "$newX_ADB_WirelessSegregation" "$newSSIDReference"
return
fi
if [ "$changedEnable" = "1" -a "$newEnable" = "false" ]; then
service_disable "$newSSIDReference"
echo "### $AH_NAME: SET <$obj.Status> <Disabled> ###"
cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "Disabled"
else
service_reconf_ap "$newEnable" "$newStatus" "$obj"
fi
;;
esac
}
service_disable() {
local ssid_obj="$1" ssid _ena
cmclient -v _ena GETV "$ssid_obj.Enable"
if [ "$_ena" = "true" ]; then
cmclient -v ssid GETV "$ssid_obj.Name"
wifi_set_bss_up "$ssid" "Down"
[ "$newX_ADB_WirelessSegregation" = "true" ] && wifi_segregate "$ssid" "false" "$ssid_obj"
wifi_set_bss_status "$ssid_obj" "Down"
fi
[ -e "$apTempFile.$ssid" ] && rm -f $apTempFile.$ssid
cmclient SET "$ssid_obj.Stats.X_ADB_Reset" "true" > /dev/null
}
service_delete() {
case "$obj" in
*"Security"* | *"WPS"*)
:
;;
*)
service_disable "$newSSIDReference"
;;
esac
}
case "$op" in
s)
service_config
;;
d)
service_delete
;;
esac
exit 0
