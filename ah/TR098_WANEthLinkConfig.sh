#!/bin/sh
AH_NAME="TR098_WANEthLinkConfig"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_set_param() {
local _obj="$1" _param="$2" _val="$3" vlan_obj link_obj
case $_param in
"X_ADB_VLANID")
cmclient -v vlan_obj GETO "Device.Ethernet.VLANTermination.*.[X_ADB_TR098Reference=$_obj]"
if [ -z "$vlan_obj" ]; then
vlan_obj=`help98_add_tr181obj "$_obj" "Device.Ethernet.VLANTermination"`
help181_set_param "$vlan_obj.LowerLayers" "$tr181obj"
fi
help181_set_param "$vlan_obj.VLANID" "$_val"
;;
"X_ADB_Enable")
cmclient -v link_obj GETO "Device.Ethernet.Link.*.[X_ADB_TR098Reference=$_obj]"
[ ${#link_obj} -gt 0 ] && help181_set_param "$link_obj.Enable" "$_val"
cmclient -v vlan_obj GETO "Device.Ethernet.VLANTermination.*.[X_ADB_TR098Reference=$_obj]"
[ ${#vlan_obj} -gt 0 ] && help181_set_param "$vlan_obj.Enable" "$_val"
;;
esac
}
service_config() {
local i
for i in X_ADB_VLANID X_ADB_Enable
do
if eval [ \${set${i}:=0} -eq 1 ]; then
eval service_set_param "$obj" "$i" \"\$new${i}\"
fi
done
}
service_add() {
tr181obj=`help98_add_tr181obj "$obj" "Device.Ethernet.Link"`
cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
help98_link_tr181obj "${obj%%.WANConnectionDevice*}.WANEthernetInterfaceConfig" "$tr181obj" "Device.Ethernet.Interface"
}
service_delete() {
local vlan_obj
cmclient -v vlan_obj GETO "Device.Ethernet.VLANTermination.*.[X_ADB_TR098Reference=$obj]"
[ ${#vlan_obj} -gt 0 ] && help181_del_object "$vlan_obj"
help98_del_bridge_availablelist "${obj%.WANEthernetLinkConfig*}"
help181_del_object "$tr181obj"
}
case "$op" in
d)
cmclient -v tr181obj GETV "$obj.X_ADB_TR181Name"
[ -n "$tr181obj" ] && service_delete
;;
a)
service_add
;;
s)
cmclient -v tr181obj GETV "$obj.X_ADB_TR181Name"
[ -n "$tr181obj" ] && service_config
;;
esac
exit 0
