#!/bin/sh
service_delete_8021Q_vlan() {
newEnable="false"
service_set_8021Q_vlan_enable
local pobj
cmclient -v pobj GETO "$this_bridge.VLANPort."
for vlan_port in $obj
do
cmclient -v vlan_port_reference GETV "$vlan_port".VLAN
if [ "$vlan_port_reference" = "$obj" ]; then
cmclient SET "$vlan_port.Enable" "false"
cmclient SET "$vlan_port.VLAN" ""
fi
done
}
service_set_8021Q_vlan() {
if [ "$newEnable" = "true" -a $changedVLANID -eq 1 ]; then
service_set_8021Q_vlan_vlanid
elif [ $changedEnable -eq 1 ]; then
[ -z "$newVLANID" ] && exit 1
service_set_8021Q_vlan_enable
fi
}
service_set_8021Q_vlan_enable() {
local manag_port
local_vlan_prepare_vbridge
cmclient -v manag_port GETV "$this_bridge".Port.[ManagementPort=true].Enable
if [ "$newEnable" = "true" ]; then
SRV_8021Q_create_vlanbridge "add" "$vbridge" "$bridge_type" ""
[ "$manag_port" = "true" ] && SRV_8021Q_populate_bridge "add" "$this_bridge" "all" "$obj"
else
[ "$manag_port" = "true" ] && SRV_8021Q_populate_bridge "rem" "$this_bridge" "all" "$obj"
SRV_8021Q_create_vlanbridge "rem" "$vbridge" "$bridge_type" ""
fi
}
service_set_8021Q_vlan_vlanid() {
local _vbridge_old
local_vlan_prepare_vbridge
SRV_8021Q_populate_bridge "rem" "$this_bridge" "all" "$obj" "VLANID" "$oldVLANID"
SRV_8021Q_create_vlanbridge "rem" "$vbridge_old" "$bridge_type" ""
SRV_8021Q_create_vlanbridge "add" "$vbridge" "$bridge_type" ""
SRV_8021Q_populate_bridge "add" "$this_bridge" "all" "$obj"
}
local_vlan_prepare_vbridge() {
this_bridge="${obj%.VLAN*}"
bridge_number=$((${this_bridge##*Bridge.}-1))
cmclient -v bridge_type GETV "$this_bridge.X_ADB_BridgeType"
vbridge="$BRIDGE_PREFIX$bridge_number$VLAN_PREFIX$newVLANID"
vbridge_old="$BRIDGE_PREFIX$bridge_number$VLAN_PREFIX$oldVLANID"
}
