#!/bin/sh
AH_NAME="TR098_LANDeviceHost"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_get()
{
local obj98="$1" param98="$2" value98="" value181="" mac="" dhcpcl dhcpaddr=""
case "$param98" in
"InterfaceType" )
cmclient -v value181 GETV "$found_obj.Layer1Interface"
case "$value181" in
*"Ethernet"* )
value98="Ethernet"
;;
*"WiFi"* )
value98="802.11"
;;
*"USB"* )
value98="USB"
;;
* )
value98="Other"
;;
esac
;;
"LeaseTimeRemaining" )
cmclient -v addr GETV "$found_obj.AddressSource"
value98="0"
case "$addr" in
"DHCP")
cmclient -v dhcpcl GETV "$found_obj.DHCPClient"
[ -n "$dhcpcl" ] && cmclient -v dhcpaddr GETO "${dhcpcl}.IPv4Address"
[ -n "$dhcpaddr" ] && cmclient -v value98 GETV "${dhcpaddr}.X_ADB_LeaseTimeRemaining"
;;
esac
;;
"VendorClassID" )
cmclient -v dhcpcl GETV "$found_obj.DHCPClient"
cmclient -v value98 GETV "$dhcpcl.Option.[Tag=60].Value"
;;
esac
echo "$value98"
}
service_delete()
{
cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
[ -n "$found_obj" ] && help181_del_object "$found_obj"
}
service_add()
{
local tr181obj=$(help98_add_tr181obj "$obj" "Device.Hosts.Host")
cmclient SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
}
case "$op" in
"a")
service_add "$obj"
;;
"d")
service_delete
;;
"g")
cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
if [ -n "$found_obj" ]; then
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
else
for arg # Arg list as separate words
do
echo ""
done
fi
;;
esac
exit 0
