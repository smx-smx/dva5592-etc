#!/bin/sh
. /etc/ah/target.sh
AH_NAME="WiFiWDS"
[ "$1" != "init" ] && [ "$user" = "$obj" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
wds_mac_config()
{
local bridge_instance
local wds_ifname_tmp
local wds_ifname
if [ "$1" = "" ];then
exit 0
fi
local wifi_ssid_reference=$1
cmclient -v wifi_ssid_ifname GETV "$wifi_ssid_reference.Name"
cmclient -v bridge_obj GETO Device.Bridging.Bridge.**.[LowerLayers=$wifi_ssid_reference]
local bridge_port=${bridge_obj%.*}
bridge_instance=${bridge_port%.*}
wifiradio_add_wds_members $wifi_ssid_ifname $2
if [ "$?" != "0" ]; then
wds_status="Error"
cmclient -u "${AH_NAME}${obj}"  SET "$obj.Status" "$wds_status" > /dev/null
exit 0
fi
cmclient -v wds_ifname_tmp GETV "$obj.Name"
if [ "$wds_ifname_tmp" = "" ];then
local wds_num=$(wifiradio_get_number_of_wds_members $wifi_ssid_ifname)
wds_ifname="wds0."$wds_num
else
wds_ifname=$wds_ifname_tmp
fi
ifconfig $wds_ifname up
if [ "$?" != "0" ]; then
wds_status="Error"
cmclient -u "${AH_NAME}${obj}"  SET "$obj.Status" "$wds_status" > /dev/null
exit 0
fi
cmclient -u "${AH_NAME}${obj}" SET "$obj.Name" "$wds_ifname" > /dev/null
cmclient -v port_num ADD "$bridge_port" > /dev/null
cmclient SET "$bridge_port.$port_num.LowerLayers" "$obj" > /dev/null
cmclient SET "$bridge_port.$port_num.Enable" "true" > /dev/null
wds_status="Enabled"
}
wds_reconfig_del()
{
local wds_enable_list
local wds_obj
cmclient -v wds_enable_list GETO "Device.WiFi.X_ADB_WDS.**.[Enable=true]"
for wds_obj in $wds_enable_list; do
if [ "$wds_obj" != "$obj" ]; then
cmclient SET "$wds_obj.Enable" "false" > /dev/null
cmclient SET "$wds_obj.Name" "" > /dev/null
else
cmclient -u "${AH_NAME}${obj}" SET "$obj.Enable" "false" > /dev/null
cmclient -u "${AH_NAME}${obj}" SET "$obj.Name" "" > /dev/null
fi
done
for wds_obj in $wds_enable_list; do
if [ "$wds_obj" != "$obj" ]; then
cmclient SET "$wds_obj.Enable" "true" > /dev/null
else
cmclient -u "${AH_NAME}${obj}" SET "$obj.Enable" "true" > /dev/null
fi
done
}
wds_reconfig()
{
local wds_enable_list
local wds_obj
cmclient -v wds_enable_list GETO "Device.WiFi.X_ADB_WDS.**.[Enable=true]"
for wds_obj in $wds_enable_list; do
if [ "$wds_obj" != "$obj" ]; then
cmclient SET "$wds_obj.Enable" "false" > /dev/null
cmclient SET "$wds_obj.Name" "" > /dev/null
else
cmclient -u "${AHNAME}${obj}" SET "$wds_obj.Enable" "false" > /dev/null
cmclient -u "${AHNAME}${obj}" SET "$wds_obj.Name" "" > /dev/null
wds_disable $newSSIDReference
fi
done
for wds_obj in $wds_enable_list; do
if [ "$wds_obj" != "$obj" ]; then
cmclient SET "$wds_obj.Enable" "true" > /dev/null
else
wds_mac_config $newSSIDReference $newRemoteMacAddress
cmclient -u "${AHNAME}${obj}" SET "$wds_obj.Enable" "true" > /dev/null
fi
done
}
wds_mac_reconfig()
{
local wds_ssid_reference=$1
	local wds_remote_mac=$2
cmclient -v wifi_ssid_ifname GETV "$wifi_ssid_reference.Name"
wifiradio_remove_wds_members $wifi_ssid_ifname
wds_reconfig
}
wds_disable()
{
local wifi_ssid_reference=$1
local wds_ifname
local bridge_port
cmclient -v wifi_ssid_ifname GETV "$wifi_ssid_reference.Name"
cmclient -v wds_ifname GETV "$obj.Name"
cmclient -v bridge_obj GETO "Device.Bridging.Bridge.**.[LowerLayers=$obj]"
cmclient DEL "$bridge_obj" > /dev/null
ifconfig $wds_ifname down
}
wds_status_clear()
{
cmclient -u "${AHNAME}${obj}" SET "$obj.Name" "" > /dev/null
cmclient -u "${AHNAME}${obj}" SET "$obj.RemoteMacAddress" "" > /dev/null
cmclient -u "${AHNAME}${obj}" SET "$obj.SSIDReference" "" > /dev/null
local wds_status=Disabled
cmclient -u "${AHNAME}${obj}" SET "$obj.Status" "$wds_status" > /dev/null
}
service_delete(){
local status
local wds_ifname
local bridge_obj
local wifi_ssid_reference=$newSSIDReference
cmclient -v wifi_ssid_ifname GETV "$wifi_ssid_reference.Name"
Get wds object status
cmclient -v status GETV "$obj.Status"
if [ "$status" = Enabled ];then
wds_disable $wifi_ssid_reference
fi
wifiradio_remove_wds_members $wifi_ssid_ifname
wds_status_clear
wds_reconfig_del
}
service_config()
{
wifi_ssid_reference=$newSSIDReference
if [ "$wifi_ssid_reference" = "" ];then
exit 0
fi
cmclient -v wifi_ssid_enable GETV "$wifi_ssid_reference.Enable"
if [ "$wifi_ssid_enable" = false ]; then
exit 0
fi
if [ "$oldEnable" = true ]; then
if [ "$newEnable" = true ];then
if [ "$newRemoteMacAddress" = "" ]; then
exit 0
fi
if [ "$oldRemoteMacAddress" = "" ]; then
wds_mac_config $newSSIDReference $newRemoteMacAddress
else
wds_mac_reconfig $newSSIDReference $newRemoteMacAddress
fi
else
wds_disable $newSSIDReference
fi
else
if [ "$newEnable" = true ]; then
if [ "$newRemoteMacAddress" != "" ]; then
wds_mac_config $newSSIDReference $newRemoteMacAddress
else
wds_status="Error_Misconfigured"
cmclient -u "${AH_NAME}${obj}"  SET "$obj.Status" "$wds_status" > /dev/null
exit 0
fi
else
wds_status="Disabled"
fi
fi
cmclient -u "${AH_NAME}${obj}"  SET "$obj.Status" "$wds_status" > /dev/null
}
if [ "$1" = "init" ]; then
wds_reconfig
fi
case "$op" in
s)
service_config
;;
d)
service_delete
;;
esac
exit 0
