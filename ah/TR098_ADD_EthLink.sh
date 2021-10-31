#!/bin/sh
AH_NAME="TR098_ADD_EthLink"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098()
{
local lowlayer="" is_wan="" tr98lowlayer="" wanDevice="" wanConn_inst="" lan_i=""
lowlayer="$newLowerLayers"
case "$lowlayer" in
*"Ethernet.Interface"*)
is_wan=`cmclient GETV "$lowlayer.Upstream"`
tr98lowlayer=`cmclient GETV "$lowlayer.$PARAM_TR098"`
if [ "$is_wan" = "true" ]; then
if [ -n "$tr98lowlayer" ]; then
wanDevice="${tr98lowlayer%.*}"
wanConn_inst=`help181_add_tr98obj "$wanDevice.WANConnectionDevice"`
help98_add_xan_xconfig "$wanDevice.WANConnectionDevice.$wanConn_inst.WANEthernetLinkConfig" "$obj" "EthernetLink$obj"
fi
else
if [ -n "$tr98lowlayer" ]; then
help98_del_bridge_availablelist "$tr98lowlayer"
help181_del_tr98obj "$tr98lowlayer"
fi
lan_i=`help181_add_tr98obj "InternetGatewayDevice.LANDevice"`
help98_add_xan_xconfig "$OBJ_IGD.LANDevice.$lan_i.LANEthernetInterfaceConfig" "$lowlayer" "EthernetIf$lowlayer"
fi
;;
*"ATM.Link"*)
tr98lowlayer=`cmclient GETV "$lowlayer.$PARAM_TR098"`
cmclient -u "EthernetLink$obj" SET "$obj.$PARAM_TR098" "$tr98lowlayer" > /dev/null
;;
*"PTM.Link"*)
cmclient -v phy GETV "$lowlayer.LowerLayers"
cmclient -v tr98lowlayer GETO InternetGatewayDevice.WANDevice.WANDSLInterfaceConfig.[X_ADB_TR181_CHAN=$phy]
wanDevice="${tr98lowlayer%%.WANDSLInterfaceConfig*}.WANConnectionDevice"
wanConn_inst=`help181_add_tr98obj "$wanDevice"`
help98_add_xan_xconfig "$wanDevice.$wanConn_inst.WANPTMLinkConfig" "$lowlayer" "PTMLink$lowlayer"
cmclient SETE $obj.$PARAM_TR098 "$wanDevice.$wanConn_inst.WANPTMLinkConfig"
;;
*"WiFi.SSID"*)
tr98lowlayer=`cmclient GETV "$lowlayer.$PARAM_TR098"`
if [ -n "$tr98lowlayer" ]; then
help98_del_bridge_availablelist "$tr98lowlayer"
help181_del_tr98obj "$tr98lowlayer"
fi
lan_i=`help181_add_tr98obj "InternetGatewayDevice.LANDevice"`
help98_add_xan_xconfig "$OBJ_IGD.LANDevice.$lan_i.WLANConfiguration" "$lowlayer" "WiFiSSID$lowlayer"
;;
*)
;;
esac
}
service_delete_tr098()
{
local tr98ref=""
local wanConn_obj=""
local lowlayer=""
local tr98lowlayer=""
local tmpObj=""
local lanDeviceObj=""
tr98ref="$newX_ADB_TR098Reference"
case "$tr98ref" in
*"WANEthernetLinkConfig"*)
help98_del_bridge_availablelist "${tr98ref%.WANEthernetLinkConfig*}"
help181_del_tr98obj "$tr98ref"			
wanConn_obj="${tr98ref%.*}"
if [ -n "$wanConn_obj" ]; then
help181_del_tr98obj "$wanConn_obj"
fi
;;
*"LANHostConfigManagement"*)
lowlayer=`cmclient GETV "$obj.LowerLayers"`
case "$lowlayer" in
*"Ethernet.Interface"*)
tr98lowlayer=`cmclient GETV "$lowlayer.$PARAM_TR098"`
if [ -n "$tr98lowlayer" ]; then
help98_del_bridge_availablelist "$tr98lowlayer"
help181_del_tr98obj "$tr98lowlayer"
fi
help98_add_lan_default "$lowlayer" "LANEthernetInterfaceConfig" "EthernetIf"
tmpObj="${tr98lowlayer#*[0-9]*.}"
lanDeviceObj="${tr98lowlayer%%.$tmpObj}"
if [ -n "$lanDeviceObj" ]; then
help98_delete_lanDevice "$lanDeviceObj"
fi
;;
*"WiFi.SSID"*)
tr98lowlayer=`cmclient GETV "$lowlayer.$PARAM_TR098"`
if [ -n "$tr98lowlayer" ]; then
help98_del_bridge_availablelist "$tr98lowlayer"
help181_del_tr98obj "$tr98lowlayer"
fi
if [ "$user" != "NoWiFi" ]; then
help98_add_lan_default "$lowlayer" "WLANConfiguration" "WiFiSSID"
fi
tmpObj="${tr98lowlayer#*[0-9]*.}"
lanDeviceObj="${tr98lowlayer%%.$tmpObj}"
if [ -n "$lanDeviceObj" ]; then
help98_delete_lanDevice "$lanDeviceObj"
fi
;;
*)
;;
esac
;;
*)
;;
esac
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
