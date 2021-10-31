#!/bin/sh
AH_NAME="WANIPReqDHCPOption"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_add() {
wanip_obj="${obj%.DHCPClient*}"
dhcpc_obj=`cmclient GETO "Device.DHCPv4.Client.[$PARAM_TR098=$wanip_obj]"`
if [ -z "$dhcpc_obj" ]; then
dhcpc_obj=`help98_add_tr181obj "$wanip_obj" "Device.DHCPv4.Client"`
ip_obj=`cmclient GETO "Device.IP.Interface.[$PARAM_TR098=$wanip_obj]"`
if [ -n "$ip_obj" ]; then
help181_set_param "$dhcpc_obj.Interface" "$ip_obj"
enable_value=`cmclient GETV "$ip_obj.Enable"`
cmclient SET "$dhcpc_obj.Enable" "$enable_value"
fi
fi
tr181obj=`help98_add_tr181obj "$obj" "$dhcpc_obj.ReqOption"`
cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
}
case "$op" in
a)
service_add
;;
d)
tr181obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
if [ -n "$tr181obj" ]; then
help181_del_object "$tr181obj"
fi
;;
esac
exit 0
