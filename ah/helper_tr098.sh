#!/bin/sh
CM_CLIENT_TR181="cmclient -u tr098"
CM_CLIENT_TR098_TR181="cmclient -u cm181"
TR98_WANETH_IFNAME="eth4"
DEFAULT_LAN_DEVICE="InternetGatewayDevice.LANInterfaces"
OBJ_IGD="InternetGatewayDevice"
PARAM_TR098="X_ADB_TR098Reference"
PARAM_TR181="X_ADB_TR181Name"
help98_get_param() {
cmclient GETV "$1"
}
help98_set_param() {
cmclient SET "$1" "$2"
}
help98_get_objects() {
cmclient GETO "$1"
}
help98_add_object() {
local tr098obj="$1" tr181obj="$2" index="" suffix=""
[ ${#tr181obj} -gt 0 ] && suffix=".[X_ADB_TR181Name=$tr181obj]"
cmclient -v index ADD ${tr098obj}${suffix}
echo $index
}
help98_del_object() {
cmclient DEL "$1"
}
help181_add_object() {
$CM_CLIENT_TR181 ADD "$1"
}
help98_add_tr181obj() {
local _tr98obj="$1" _tr181obj="$2"
newinst=`help181_add_object "$_tr181obj"`
$CM_CLIENT_TR181 SET "$_tr181obj"."$newinst"."$PARAM_TR098" "$_tr98obj" > /dev/null
echo -n "$_tr181obj.$newinst"
}
help181_del_object() {
$CM_CLIENT_TR181 DEL "$1"
}
help181_set_param() {
set_param=`$CM_CLIENT_TR181 SET "$1" "$2"`
}
help98_link_tr181obj() {
local tr98ref="$1" tr181obj="$2" lower_obj="$3"
cmclient -v tr181_lower GETO  "$lower_obj.*.[$PARAM_TR098=$tr98ref]"
if [ -n "$tr181_lower" ]; then
help181_set_param "$tr181obj.LowerLayers" "$tr181_lower"
return 1
fi
return 0
}
help181_del_tr98obj() {
$CM_CLIENT_TR098_TR181 DEL "$1"
}
help181_add_tr98obj() {
local tr098obj="$1" tr181obj="$2" idx="$3" index="" suffix=""
[ ${#tr181obj} -gt 0 ] && suffix=".[X_ADB_TR181Name=${tr181obj}]"
if [ ${#idx} -gt 0 -a ${#suffix} -gt 0 ]; then
$CM_CLIENT_TR098_TR181 -v index ADD "${tr098obj}". ${idx}
$CM_CLIENT_TR098_TR181 SET "${tr098obj}.${idx}".X_ADB_TR181Name "${tr181obj}" > /dev/null
else
$CM_CLIENT_TR098_TR181 -v index ADD "${tr098obj}${suffix}". $idx
fi
echo "$index"
}
help98_switch_link_type() {
local _tr98="$1"
cmclient -v link_type GETV "$_tr98.WANDSLLinkConfig.LinkType"
case "$link_type" in
"IPoA" | "CIP" | "PPPoA" )
echo -n "false"
;;
"EoA" | "PPPoE" )
echo -n "true"
;;
esac
}
help98_get_connstatus() {
local _status181="$1" _status098=""
case "$_status181" in
"Up" )
_status098="Connected"
;;
* )
_status098="Disconnected"
;;
esac
echo -n "$_status098"
}
help98_get_linkstatus() {
local _status181="$1" _status098=""
case "$_status181" in
"Up"|"Down")
_status098="$_status181"
;;
"LowerLayerDown")
_status098="Down"
;;
"Unknown"|"NotPresent"|"Error"|"Dormant")
_status098="Unavailable"
;;
esac
echo -n "$_status098"
}
help98_get_ifstatus() {
[ "$1" != "_status181" ] && local _status181
[ "$1" != "_tr098val" ] && local _tr098val
_status181="$2"
case "$_status181" in
"Up"|"Error")
_tr098val="$_status181"
;;
"Down")
_tr098val="NoLink"
;;
*)
_tr098val="Disabled"
;;
esac
eval $1='$_tr098val'
}
help98_add_bridge_availablelist() {
local _tr098obj="$1" _iface_type="$2" _found=""
avail_obj="InternetGatewayDevice.Layer2Bridging.AvailableInterface"
cmclient -v _found GETO "$avail_obj.*.[InterfaceReference=$_tr098obj]"
if [ ${#_found} -eq 0 ]; then
new_inst=`help98_add_object "$avail_obj"`
avail_iface="$avail_obj.$new_inst"
help98_set_param "$avail_iface.AvailableInterfaceKey" "$new_inst"
help98_set_param "$avail_iface.InterfaceType" "$_iface_type"
help98_set_param "$avail_iface.InterfaceReference" "$_tr098obj"
fi
}
help98_del_bridge_availablelist() {
local _tr098obj="$1" _found=""
avail_obj="InternetGatewayDevice.Layer2Bridging.AvailableInterface"
cmclient -v _found GETO "$avail_obj.*.[InterfaceReference=$_tr098obj]"
if [ ${#_found} -gt 0 ]; then
help98_del_object "$_found"
fi
}
help98_delete_lanDevice() {
local lanDevice="$1"
cmclient -v lanEthNum GETV "$lanDevice.LANEthernetInterfaceNumberOfEntries"
if [ "$lanEthNum" = "0" ]; then
cmclient -v lanUsbNum GETV "$lanDevice.LANUSBInterfaceNumberOfEntries"
if [ "$lanUsbNum" = "0" ]; then
cmclient -v wLanNum GETV "$lanDevice.LANWLANConfigurationNumberOfEntries"
[ "$wLanNum" = "0" ] && help181_del_tr98obj "$lanDevice"
fi
fi
}
help98_bridge_landevice() {
local bridge="$1" tr181bridge="$2" port_id="" intf_ref="" lan_device="" bobjs ll_obj="" mgmt_port="" tr098_ref=""
cmclient -v bobjs GETO "$bridge.Port"
for port in $bobjs; do
cmclient -v port_id GETV "$port.PortInterface"
cmclient -v intf_ref GETV "InternetGatewayDevice.Layer2Bridging.AvailableInterface.*.[AvailableInterfaceKey=$port_id].InterfaceReference"
case "$intf_ref" in
*"LANDevice"*)
lan_device=`help_strextract "$intf_ref" "InternetGatewayDevice.LANDevice.*."`
break
;;
esac
done
if [ -z "$lan_device" ]; then
cmclient -v mgmt_port GETO "$tr181bridge.Port.*.[ManagementPort=true]"
if [ -n "$mgmt_port" ]; then
cmclient -v ll_obj GETO "Device.**.[X_ADB_ActiveLowerLayer>$mgmt_port]"
if [ -n "$ll_obj" ]; then
cmclient -v tr098_ref GETV $ll_obj.$PARAM_TR098
case "$tr098_ref" in
*"LANDevice"*)
lan_device=`help_strextract "$tr098_ref" "InternetGatewayDevice.LANDevice.*."`
break
;;
esac
fi
fi
fi
echo "$lan_device"
}
help98_add_lan_default() {
local tr181obj="$1" obj="$2" user="$3" suffix=""
[ "$obj" != "WLANConfiguration" ] && suffix="$tr181obj"
obj_i=`help181_add_tr98obj "$DEFAULT_LAN_DEVICE.$obj" "$suffix"`
objIntf="$DEFAULT_LAN_DEVICE.$obj.$obj_i"
cmclient -u "$user$tr181obj" SET "$tr181obj.$PARAM_TR098" "$objIntf"
if [ "$obj" = "WLANConfiguration" ]; then
cmclient -v ap_obj GETO "Device.WiFi.AccessPoint.[SSIDReference=$tr181obj]"
[ ${#ap_obj} -gt 0 ] && cmclient -u "WiFiAP$ap_obj" SET "$ap_obj.$PARAM_TR098" "$objIntf"
$CM_CLIENT_TR098_TR181 SET "$objIntf.X_ADB_TR181_SSID" "$tr181obj"
$CM_CLIENT_TR098_TR181 SET "$objIntf.X_ADB_TR181_AP" "$ap_obj"
fi
}
help98_add_xan_xconfig() {
local obj_path="$1" obj_tr181="$2" user="$3"
case "$obj_path" in
*"LANDevice"*)
case "$obj_path" in
*"WLANConfiguration"*)
obj_id=`help181_add_tr98obj "$obj_path"`
help98_add_bridge_availablelist "$obj_path.$obj_id" "LANInterface"
cmclient -u "$user" SET "$obj_tr181.$PARAM_TR098" "$obj_path.$obj_id"
cmclient -v ap_obj GETO "Device.WiFi.AccessPoint.[SSIDReference=$obj_tr181]"
if [ -n "$ap_obj" ]; then
cmclient -u "WiFiAP$ap_obj" SET "$ap_obj.$PARAM_TR098" "$obj_path.$obj_id"
fi
$CM_CLIENT_TR098_TR181 SET "$obj_path.$obj_id.X_ADB_TR181_SSID" "$obj_tr181"
$CM_CLIENT_TR098_TR181 SET "$obj_path.$obj_id.X_ADB_TR181_AP" "$ap_obj"
cmclient -v radio GETV $obj_tr181.LowerLayers
$CM_CLIENT_TR098_TR181 SET "$obj_path.$obj_id.X_ADB_TR181Name" "$radio"
;;
*)
obj_id=`help181_add_tr98obj "$obj_path" "$obj_tr181"`
cmclient -u "$user" SET "$obj_tr181.$PARAM_TR098" "$obj_path.$obj_id"
help98_add_bridge_availablelist "$obj_path.$obj_id" "LANInterface"
;;
esac
;;
*"WANDevice"*)
obj_id=`help181_add_tr98obj "$obj_path" "$obj_tr181"`
cmclient -u "$user" SET "$obj_tr181.$PARAM_TR098" "$obj_path"
help98_add_bridge_availablelist "${obj_path%.*}" "WANInterface"
;;
esac
}
