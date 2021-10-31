#!/bin/sh
AH_NAME="TR098_ADD_NATPortMapping"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098()
{
local tr98ref="" nat_inst="" creator
if [ $changedInterface -eq 0 ]; then
return
fi
tr98ref=`cmclient GETV "$newInterface.$PARAM_TR098"`
case "$tr98ref" in
*"WANConnectionDevice"*)
oldtr98ref="`cmclient GETV $obj.$PARAM_TR098`"
if [ -n "$oldtr98ref" ]; then
help181_del_tr98obj "$oldtr98ref" > /dev/null
fi
nat_inst=`help181_add_tr98obj "$tr98ref.PortMapping" "$obj"`
cmclient SET "$obj.$PARAM_TR098" "$tr98ref.PortMapping.$nat_inst" > /dev/null
cmclient -v creator GETV "$obj.X_ADB_Creator"
[ "$creator" = "UPnP" ] && cmclient SETS "$tr98ref.PortMapping.$nat_inst" "0"
;;
esac
}
service_delete_tr098()
{
if [ -n "$newX_ADB_TR098Reference" ]; then
help181_del_tr98obj "$newX_ADB_TR098Reference"
fi
}
case "$op" in
"s")
service_align_tr098
;;
"d")
service_delete_tr098
;;
esac
exit 0
