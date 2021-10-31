#!/bin/sh
AH_NAME="TR098_ADD_BridgeVLAN"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098()
{
local bridgeVLANId="" this_bridge="" this_bridge="${obj%.VLAN*}"
local bridgeId=${this_bridge##*Bridge.}
if [ -n "$bridgeId" ]; then
bridgeVLANId=`help181_add_tr98obj "InternetGatewayDevice.Layer2Bridging.Bridge.$bridgeId.VLAN" "$obj"`
cmclient -u "BridgingBridge$obj" SET "$obj.$PARAM_TR098" "InternetGatewayDevice.Layer2Bridging.Bridge.$bridgeId.VLAN.$bridgeVLANId"
fi
}
service_delete_tr098()
{
local tr98ref="$newX_ADB_TR098Reference"
if [ -n "$tr98ref" ]; then
help181_del_tr98obj "$tr98ref"
fi
}
case "$op" in
"a")
service_align_tr098
;;
"d")
service_delete_tr098
;;
esac
exit 0
