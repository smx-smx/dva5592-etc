#!/bin/sh
AH_NAME="LANHostIPInterface"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_link_stack()
{
local _tr98obj="$1"
local _tr181obj="$2"
local tr98_landevice=""
local if_key=""
local bridge_port=""
local bridge_path=""
local bridge_manag_port=""
local eth_link=""
tr98_landevice="${_tr98obj%.LANHostConfigManagement*}"
for if_key in `cmclient GETV "InternetGatewayDevice.Layer2Bridging.AvailableInterface.*.[InterfaceReference>$tr98_landevice].AvailableInterfaceKey"`
do
bridge_port=`cmclient GETO "InternetGatewayDevice.Layer2Bridging.Bridge.*.Port.*.[PortInterface=$if_key]"`
if [ -n "$bridge_port" ]; then
bridge_path="${bridge_port%.Port*}"
break;
fi
done
if [ -n "$bridge_path" ]; then
bridge_manag_port=`cmclient GETO "Bridging.Bridge.*.Port.*.[$PARAM_TR098=$bridge_path]"`
eth_link=`cmclient GETO "Device.Ethernet.Link.*.[$PARAM_TR098=${_tr98obj%.IPInterface*}]"`
if [ -z "$eth_link" ]; then
eth_link=`help98_add_tr181obj "${_tr98obj%.IPInterface*}" "Device.Ethernet.Link"`
fi
help181_set_param "$eth_link"."LowerLayers" "$bridge_manag_port"
cmclient SET "$eth_link"."Enable" "true"
help181_set_param "$_tr181obj.LowerLayers" "$eth_link"
fi
}
service_add() {
local lanhost_obj="${obj%.IPInterface*}"
local tr181ref=`cmclient GETV "$lanhost_obj.$PARAM_TR181"`
if [ -n "$tr181ref" ]; then
ip_found=`cmclient GETO "Device.IP.Interface.[$PARAM_TR098=$lanhost_obj]"`
if [ -n "$ip_found" ]; then
help181_set_param "$tr181ref.Interface" "$ip_found"
tr181obj=`help98_add_tr181obj "$obj" "$ip_found.IPv4Address"`
service_link_stack "$obj" "$ip_found"
cmclient SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
return
fi
fi
ip_found=`help98_add_tr181obj "$lanhost_obj" "Device.IP.Interface"`
cmclient SET  "$ip_found"."Enable" "true" > /dev/null
if [ -n "$tr181ref" ]; then
help181_set_param "$tr181ref.Interface" "$ip_found"
fi
tr181obj=`help98_add_tr181obj "$obj" "$ip_found.IPv4Address"`
service_link_stack "$obj" "$ip_found"
cmclient SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
}
service_delete()
{
local ipv4_search=""
local lanhost_search=""
local is_ipv4=""
local ipv4_found=0
local found_obj=`cmclient GETV "$obj.$PARAM_TR181"`
if [ -n "$found_obj" ]; then
help181_del_object "$found_obj"
ipv4_search="${found_obj%.IPv4Address*}"
lanhost_search="${obj%.IPInterface*}"
if [ -n "$lanhost_search" ]; then
for is_ipv4 in `cmclient GETO "$ipv4_search.IPv4Address.*.[$PARAM_TR098>$lanhost_search]"`
do
ipv4_found=1
break;
done
if [ "$ipv4_found" -ne 1 ]; then
help181_del_object "$ipv4_search"
eth_link=`cmclient GETO "Device.Ethernet.Link.*.[$PARAM_TR098=$lanhost_search]"`
if [ -n "$eth_link" ]; then
				help181_del_object "$eth_link"
fi
fi
fi
fi
}
case "$op" in
"a")
service_add
;;
"d")
service_delete
;;
esac
exit 0
