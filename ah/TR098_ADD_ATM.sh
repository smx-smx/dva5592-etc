#!/bin/sh
AH_NAME="TR098_ADD_ATM"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098()
{
local tr98lowlayer
local wanObj=""
local wanConn_inst=""
cmclient -v tr98lowlayer GETV "$newLowerLayers.$PARAM_TR098"
wanObj="${tr98lowlayer%%.WANDSLInterfaceConfig*}.WANConnectionDevice"
wanConn_inst=`help181_add_tr98obj "$wanObj"`
help181_add_tr98obj "$wanObj.$wanConn_inst.WANDSLLinkConfig" "$obj"
cmclient -u "ATMLink$obj" SET "$obj.$PARAM_TR098" "$wanObj.$wanConn_inst.WANDSLLinkConfig" > /dev/null
}
service_delete_tr098()
{
local tr98ref=""
local wanConn_obj=""
tr98ref="$newX_ADB_TR098Reference"
if [ -n "$tr98ref" ]; then
help98_del_bridge_availablelist "${tr98ref%.WANDSLLinkConfig*}"
help181_del_tr98obj "$tr98ref"
wanConn_obj="${tr98ref%.*}"
if [ -n "$wanConn_obj" ]; then
help181_del_tr98obj "$wanConn_obj"
fi
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
