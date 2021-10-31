#!/bin/sh
service_delete_8021Q_vlanport() {
newEnable="false"
service_set_8021Q_vlanport_enable
}
service_set_8021Q_vlanport() {
[ "$user" = "init" ] && (service_set_8021Q_vlanport_enable; return)
if [ $changedEnable -eq 1 ]; then
if [ -z "$newPort" -o -z "$newVLAN" -o -z "$newUntagged" ]; then
echo "### $AH_NAME(802.1Q): CANNOT ENABLE [$obj] (check .Port, .VLAN and .Untagged)"
exit 1
fi
service_set_8021Q_vlanport_enable
elif [ "$newEnable" = "true" -a \( $changedVLAN -eq 1 -o $changedPort -eq 1 -o $changedUntagged -eq 1 \) ]; then
if [ $changedVLAN -eq 1 ]; then
service_set_8021Q_vlanport_vlan
fi
if [ $changedPort -eq 1 ]; then
service_set_8021Q_vlanport_port
fi
if [ $changedUntagged -eq 1 ]; then
service_set_8021Q_vlanport_untagged
fi
fi
}
service_set_8021Q_vlanport_enable() {
local _interface _vlan_id
help_lowlayer_ifname_get "_interface" "$newPort"
cmclient -v _vlan_id GETV $newVLAN.VLANID
if [ "$newEnable" = "true" ]; then
local_vlanport_populate_bridge "add" $_interface $_vlan_id
else	############### FALSE ##################
local_vlanport_populate_bridge "rem" $_interface $_vlan_id
fi
}
service_set_8021Q_vlanport_vlan() {
local _interface _vlan_id _vlan_id_old _port_ingress
help_lowlayer_ifname_get "_interface" "$newPort"
cmclient -v _vlan_id GETV $newVLAN.VLANID
cmclient -v _vlan_id_old GETV $oldVLAN.VLANID
if [ "$newUntagged" = "true" ]; then
cmclient -v _port_ingress GETV $newPort.IngressFiltering
[ "$_port_ingress" = "false" ] && return
fi
local_vlanport_populate_bridge "rem" "$_interface" "$_vlan_id_old"
local_vlanport_populate_bridge "add" "$_interface" "$_vlan_id"
}
service_set_8021Q_vlanport_port() {
local _interface _vlan_id _interface_old
help_lowlayer_ifname_get "_interface" "$newPort"
cmclient -v _vlan_id GETV $newVLAN.VLANID
help_lowlayer_ifname_get "_interface_old" "$oldPort"
local_vlanport_populate_bridge "rem" $_interface_old $_vlan_id
local_vlanport_populate_bridge "add" $_interface $_vlan_id
}
service_set_8021Q_vlanport_untagged() {
local _interface _vlan_id _untagged_old
help_lowlayer_ifname_get "_interface" "$newPort"
cmclient -v _vlan_id GETV $newVLAN.VLANID
if [ "$newUntagged" = "true" ]; then
local_vlanport_populate_bridge "rem" "$_interface" "$_vlan_id" "false"
else
local_vlanport_populate_bridge "rem" "$_interface" "$_vlan_id" "true"
fi
local_vlanport_populate_bridge "add" "$_interface" "$_vlan_id"
SRV_8021Q_update_filters "$newPort"
}
local_vlanport_populate_bridge() {
local _command="$1" _interface="$2" _vlan_id="$3" _untagged="$4" # OPTIONAL
local _port_ingressfiltering _check _this_bridge _management_port \
_management_port_pvid _management_port_infiltering \
_vlan_port="$newPort" _vlan_obj="$newVLAN"
[ "$_command" != "add" ] && _vlan_port="$oldPort" && _vlan_obj="$oldVLAN"
[ -z "$_untagged" ] && _untagged="$newUntagged"
[ "$_untagged" = "false" ] && [ "$_command" = "add" ] && \
SRV_8021Q_create_vlaniface "add" "$_interface" "$_vlan_id" "$newPort"
_this_bridge="${obj%.VLANPort*}"
cmclient -v _check GETV "$_this_bridge.VLAN.[VLANID=$_vlan_id].Enable"
if [ "$_check" = "true" ]; then
cmclient -v _check GETV $newPort.Enable
if [ "$_check" = "true" ]; then
cmclient -v _port_ingressfiltering GETV $newPort.IngressFiltering
if [ "$_port_ingressfiltering" = "true" ]; then
cmclient -v _management_port GETO "$_this_bridge.Port.*.[ManagementPort=true]"
cmclient -v _management_port_pvid GETV "$_management_port.PVID"
cmclient -v _management_port_infiltering GETV "$_management_port.IngressFiltering"
[ "$_management_port_infiltering" = "true" ] && [ "$_vlan_id" = "$_management_port_pvid" ] && \
_port_ingressfiltering="false"	# trick to force interface to be managed on the base bridge (br0)
fi ####################
SRV_8021Q_populate_bridge "$_command" "$_this_bridge" "$_vlan_port" "$_vlan_obj" "Untagged" "$_untagged"
[ "$_untagged" = "false" ] && [ "$_command" = "rem" ] && \
SRV_8021Q_create_vlaniface "rem" "$_interface" "$_vlan_id"
fi
fi
}
