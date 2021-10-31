#!/bin/sh
AH_NAME="UPnP"
[ "$user" = "yacs" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
[ -f /tmp/upgrading.lock ] && [ "$op" != "g" ] && exit 0
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_svc.sh
any_change() {
local ext_iface="$1"
[ "$newX_ADB_CurrentIface" != "$ext_iface" ] && return 1
[ $setEnable -eq 1 ] && return 1
[ $changedX_ADB_ExternalInterface -eq 1 ] && return 1
[ $changedX_ADB_AutoExternalInterface -eq 1 ] && return 1
[ $changedX_ADB_LanInterface -eq 1 ] && return 1
[ $changedX_ADB_NotifyInterval -eq 1 ] && return 1
return 0
}
upnp_service() {
local command="$1"
local restart_check=""
local UPnP_arg_lan_net_device="$2"
local UPnP_arg_port="" UPnP_arg_https_port=""
local UPnP_arg_iface="$3"
local UPnP_arg_extifnum="$4"
local UPnP_arg_notify_interval="$5"
local UPnP_pid=`pidof miniupnpd`
[ -z "$UPnP_arg_iface"  ] && UPnP_arg_iface="dummy"
any_change "$UPnP_arg_iface"
restart_check="$?"
if [ $restart_check -eq 0 ] && [ -n "$UPnP_pid" ]; then
return 0
fi
echo "### $AH_NAME: Stopping UPnP service" > /dev/console
help_svc_stop miniupnpd
if [ "$command" = "start" ] && [ -n "$UPnP_arg_lan_net_device" ]; then
UPnP_arg_lan_net_device="-a $UPnP_arg_lan_net_device"
[ -n "$UPnP_arg_extifnum" ] && UPnP_arg_extifnum="-I $UPnP_arg_extifnum"
[ -n "$UPnP_arg_notify_interval" ] && UPnP_arg_notify_interval="-t $UPnP_arg_notify_interval"
[ $newX_ADB_Port -gt 0 ] && UPnP_arg_port="-p $newX_ADB_Port"
[ ${#UPnP_arg_https_port} -gt 0 ] && UPnP_arg_https_port="-H $UPnP_arg_https_port"
cmclient -u "$AH_NAME" SET "$obj.X_ADB_CurrentIface" "$UPnP_arg_iface"
echo "### $AH_NAME:  Starting UPnP service" > /dev/console
echo "###            miniupnpd -d -i $UPnP_arg_iface $UPnP_arg_lan_net_device -N $UPnP_arg_extifnum $UPnP_arg_notify_interval $UPnP_arg_port" > /dev/console
help_svc_start "miniupnpd -d -i $UPnP_arg_iface $UPnP_arg_lan_net_device -N $UPnP_arg_extifnum $UPnP_arg_notify_interval $UPnP_arg_port" 'miniupnpd'
fi
}
service_reconf() {
local ExtInt_num=""
local ExtInt_name=""
local Notify_interval=""
local LanNetworkDevice=""
local UPnP_pid=""
local temp=""
local ipv4_addresses
ExtInt_num=`expr "$newX_ADB_ExternalInterface" : 'Device.IP.Interface.\([0-9]*\)'`
help_lowlayer_ifname_get ExtInt_name "$newX_ADB_ExternalInterface"
[ -z "$ExtInt_name" ] && ExtInt_name="dummy"
if [ "$newX_ADB_LanInterface" = "" ]; then
cmclient -v temp GETO "Device.IP.Interface.[Status=Up].[X_ADB_Upstream=false]"
for newX_ADB_LanInterface in $temp; do
cmclient -v ipv4_addresses GETV $newX_ADB_LanInterface".IPv4Address.[Enable=true].IPAddress"
[ ${#ipv4_addresses} -ne 0 ] && break
newX_ADB_LanInterface=''
done
fi
help_lowlayer_ifname_get LanNetworkDevice "$newX_ADB_LanInterface"
if [ -n "$LanNetworkDevice" ]; then
cmclient -v Notify_interval GETV "Device.UPnP.Device.X_ADB_NotifyInterval"
upnp_service "start" "$LanNetworkDevice" "$ExtInt_name" "$ExtInt_num" "$Notify_interval"
UPnP_pid=`pidof miniupnpd`
[ -z "$UPnP_pid" ] && return 1
else
echo "### $AH_NAME: ERROR - unable to start UPnP. Missing LAN address."
return 1
fi
}
service_del() {
[ "$newEnable" = "true" ] && upnp_service "stop"
}
service_config() {
if [ $changedUPnPMediaServer -eq 1 ]; then
cmclient SET Device.DLNA.X_ADB_Device.Enable "$newUPnPMediaServer"
fi
if [ "$newEnable" = "true" ]; then
service_reconf
elif [ $changedEnable -eq 1 ]; then
upnp_service "stop"
fi
}
case "$op" in
d)
service_del
;;
s)
service_config
;;
esac
exit 0
