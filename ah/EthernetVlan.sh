#!/bin/sh
AH_NAME="EthernetVLAN"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_status.sh
. /etc/ah/target.sh
. /etc/ah/helper_stats.sh
. /etc/ah/IPv6_helper_functions.sh
service_reconf() {
local _path="$1" _status="$2" _enable="$3" _ifname="$4" _lowlayer="$5"
local _vid="$6" _prio="$7" new_status
help_get_status_from_lowerlayers new_status "$_path" "$_enable" "$_lowlayer"
[ "$_enable" = "false" ] && \
align_upper_layers "$_path" "$_enable" "Device.Bridging.Bridge.*.Port"
service_do_reconf "$_path" "$_ifname" "$_enable" "$_vid" "$_prio"
[ "$_enable" = "true" ] && \
align_upper_layers "$_path" "$_enable" "Device.Bridging.Bridge.*.Port"
cmclient SET -u "${AH_NAME}${_path}" "$_path.Status" "$new_status"
}
service_delete() {
local lowlayer_ifname
help_lowlayer_ifname_get lowlayer_ifname "$newLowerLayers"
service_do_reconf "$obj" "$lowlayer_ifname" "false" "$newVLANID" "$newX_ADB_8021pPrio"
}
service_do_reconf() {
local _path="$1" _ifname="$2" _enable="$3" _vid="$4" _prio="$5" i=0 mtu _curr_prio
if [ -n "$_vid" -a -n "$_ifname" ]; then
[ "$(ip link show dev $_ifname up)" != "" ] && _old_status="true" || _old_status="false"
if [ "$_enable" = "true" ]; then
help_if_link_change "$_ifname" "Up" "$AH_NAME"
vlan_cmd="add $_ifname $_vid"
else
help_if_link_change "$_ifname.$_vid" "Down" "$AH_NAME"
vlan_cmd="rem $_ifname.$_vid"
fi
echo "### $AH_NAME: Executing <vconfig $vlan_cmd> ###"
vconfig $vlan_cmd
cmd_ret=$?
if [ "$_enable" = "true" ]
then
help_ipv6_reconf_iface "$_ifname.$_vid"
fi
while [ $i -lt 8 ]; do
get_elem_n _curr_prio $_prio "$((i + 1))" ","
if [ "${_curr_prio:=-1}" != "-1" ]; then
vconfig set_egress_map $_ifname.$_vid $i $_curr_prio
else
vconfig set_egress_map $_ifname.$_vid $i $i
fi
i=$((i + 1))
done
read mtu < /sys/class/net/$_ifname/mtu
[ -n "$mtu" ] && mtu=$((mtu - 4))
[ "$_enable" = "$_old_status" -a "$_enable" = "true" ] && help_if_link_change "$_ifname.$_vid" "Up" "$AH_NAME" "$mtu"
fi
}
service_get_ifname() {
help_lowlayer_ifname_get $1 "${2%%.Stats}"
}
service_get() {
[ -z "$2"] && echo ""
help_get_base_stats_core $1 $2 currentVal
eval "parVal=\$new$3"
if [ ${parVal:=0} -le $currentVal ]; then
echo $((currentVal-parVal))
else
echo $(((1<<32) - (parVal - currentVal)))
fi
}
service_config() {
case "$obj" in
Device.Ethernet.VLANTermination.*.Stats)
if [ "$setX_ADB_Reset" = "1" -a "$newX_ADB_Reset" = "true" ]; then
help_reset_stats $obj
fi
;;
Device.Ethernet.VLANTermination.*)
local lowlayer_ifname oifname _status macOffset=""
cmclient -v macOffset GETV $obj.X_ADB_MacOffset
if [ "$user" = "InterfaceStack" -a "$setEnable" = "1" ]; then
help_get_status_from_lowerlayers _status "$obj"
if [ "$_status" = "Up" ]; then
local lowlayer_ifname vlanid prio
help_lowlayer_ifname_get lowlayer_ifname "$newLowerLayers" $newX_ADB_ActiveLowerLayer
help_if_link_change "$lowlayer_ifname" "$_status" "$AH_NAME"
cmd_ret=0
service_do_reconf "$obj" "$lowlayer_ifname" "true" "$newVLANID" "$newX_ADB_8021pPrio"
[ "$cmd_ret" -eq 0 ] && \
align_upper_layers "$obj" "true" "Device.Bridging.Bridge.*.Port"
[ $macOffset -gt -1 ] && set_mac_offset  "$obj" "$lowlayer_ifname"
fi
[ "$newStatus" != "$_status" ] && \
cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "$_status"
exit 0
fi
help_lowlayer_ifname_get lowlayer_ifname "$newLowerLayers" "$newX_ADB_ActiveLowerLayer"
if [ $changedVLANID -eq 1 -a "$newEnable" = "true" ] || [ "$setX_ADB_ActiveLowerLayer" = "1" -a "$newEnable" = "true" ]; then
[ $changedX_ADB_ActiveLowerLayer = 1 ] && help_lowlayer_ifname_get oifname "$oldLowerLayers" "$oldX_ADB_ActiveLowerLayer" || oifname=$lowlayer_ifname
service_reconf "$obj" "$newStatus" "false" "$oifname" "$newLowerLayers" "$oldVLANID" "$newX_ADB_8021pPrio"
sleep 1
service_reconf "$obj" "Down" "true" "$lowlayer_ifname" "$newLowerLayers" "$newVLANID" "$newX_ADB_8021pPrio"
elif [ $changedEnable -eq 1 ] || [ "$changedX_ADB_8021pPrio" = "1" -a "$newEnable" = "true" ]; then
service_reconf "$obj" "$newStatus" "$newEnable" "$lowlayer_ifname" "$newLowerLayers" "$newVLANID" "$newX_ADB_8021pPrio"
fi
[ $changedVLANID -eq 1 -a ${#oldName} -ne 0 ] && echo "$oldName" > /proc/net/nf_conntrack_flush
[ $macOffset -gt -1 ] && set_mac_offset  "$obj" "$lowlayer_ifname"
;;
esac
}
case "$op" in
d)
service_delete
;;
g)
service_get_ifname ifname $obj
for arg # Arg list as separate words
do
service_get "$obj.$arg" $ifname $arg
done
;;
s)
service_config
;;
esac
exit 0
