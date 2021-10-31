#!/bin/sh
AH_NAME="TR098_ADD_PTM"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_delete_tr098()
{
local tr98ref=""
local wanConn_obj=""
tr98ref="$newX_ADB_TR098Reference"
if [ -n "$tr98ref" ]; then
help98_del_bridge_availablelist "${tr98ref%.WANPTMLinkConfig*}"
help181_del_tr98obj "$tr98ref"
wanConn_obj="${tr98ref%.*}"
if [ -n "$wanConn_obj" ]; then
help181_del_tr98obj "$wanConn_obj"
fi
fi
}
case "$op" in
"d")
service_delete_tr098
;;
esac
exit 0
