#!/bin/sh
AH_NAME="NATPortMapping"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_add() {
local obj181= wan_obj= ip_obj=
obj181=`help98_add_tr181obj "$obj" "Device.NAT.PortMapping"`
cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$obj181"
wan_obj="${obj%.PortMapping*}"
cmclient -v ip_obj GETO "Device.IP.Interface.*.[$PARAM_TR098=$wan_obj]"
help181_set_param "$obj181.Interface" "$ip_obj"
}
service_get() {
local obj98="$1" param98="$2" obj181="$3" value98=
case "$param98" in
"InternalPort")
cmclient -v value98 GETV $obj181.InternalPort
[ "$value98" = "0" ] && cmclient -v value98 GETV $obj181.ExternalPort
;;
esac
echo "$value98"
}
service_set() {
local obj98="$1" obj181="$2"
if [ "${setRemoteHost:=0}" -eq 1 ]; then
if [ ${#newRemoteHost} -eq 0 ] || help_is_valid_ip "$newRemoteHost"; then
cmclient SET "$obj181.RemoteHost $newRemoteHost"
else
exit 7
fi
fi
if [ "${setInternalClient:=0}" -eq 1 ]; then
if [ "$newInternalClient" != "255.255.255.255" ]; then
cmclient -u "tr098" SET "$obj181.InternalClient $newInternalClient"
else
exit 7
fi
fi
}
found_obj=
cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
case "$op" in
a)
service_add
;;
d)
[ ${#found_obj} -ne 0 ] && help181_del_object "$found_obj"
;;
g)
if [ ${#found_obj} -ne 0 ]; then
for arg; do
service_get "$obj" "$arg" "$found_obj"
done
fi
;;
s)
[ ${#found_obj} -ne 0 ] && service_set "$obj" "$found_obj"
;;
esac
exit 0
