#!/bin/sh
AH_NAME="BridgingBridge"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/Bridge8021Q.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_status.sh
. /etc/ah/helper_mtu.sh
. /etc/ah/helper_bridge.sh
. /etc/ah/target.sh
. /etc/ah/helper_svc.sh
. /etc/ah/IPv6_helper_functions.sh
service_get() {
local get_path="$1" buf=""
case "$get_path" in
*)
;;
esac
}
service_reconf() {
local _path=$1 _status=$2 _enable=$3 new_status
[ "$_enable" = "false" ] && new_status="Disabled" || new_status="Enabled"
if [ "$new_status" != "$_status" ]; then
echo "### $AH_NAME: SET <$_path.Status> <$new_status> ###"
cmclient SET -u "${AH_NAME}${_path}" "$_path.Status" "$new_status"
cmclient SET -u "${AH_NAME}${_path}" "$_path.Port.1.Enable" "$_enable"
fi
}
service_mtu() {
local lowlayer="" port=""
cmclient -v port GETO "$obj.Port.[ManagementPort=false]"
for port in $port; do
cmclient -v lowlayer GETV "$port".LowerLayers
help_set_mtu "$lowlayer" "$port"
done
}
service_multicast_isolation() {
local command="$1" side="$2" inobj outobj inport outport cmd full_port_list _lower group g
cmclient -v full_port_list GETO "$obj.Port.[ManagementPort=false].[Enable=true]"
[ "$command" = "start" ] && cmd="-A" || cmd="-D"
[ -z "$2" ] && return 0
cmclient -v group GETV "Device.Services.X_ADB_IGMPProxy.SkipGroups"
for inobj in $full_port_list; do
is_${side}_intf "$inobj" && continue
cmclient -v _lower GETV "$inobj".LowerLayers
help_lowlayer_ifname_get inport "$_lower"
if [ ${#group} -ne 0 ]; then
IFS=','
set -- $group
unset IFS
for g; do
ebtables -t filter "$cmd" FORWARD -i "$inport" -p IPv4 --ip-dst $g -j ACCEPT
done
fi
for outobj in $full_port_list; do
is_${side}_intf "$outobj" && continue
cmclient -v _lower GETV "$outobj".LowerLayers
help_lowlayer_ifname_get outport $_lower
[ "$outport" = "$inport" ] && continue
ebtables -t filter "$cmd" FORWARD -i "$inport" -o "$outport" -d 01:00:5e:00:00:00/FF:FF:FF:00:00:00 -j DROP
done
done
}
service_multicast_leaving() {
local option="$1" cmd br_name
[ "$option" = "true" ] && cmd="-A" || cmd="-D"
cmclient -v br_name GETV "$obj.Port.[ManagementPort=true].[Enable=true].Name"
ebtables -t filter "$cmd" FORWARD -l igmp_control --igmp-leave --logical-in "$br_name" -j DROP
}
service_lanrouting() {
local brobj="$1" allow="$2" delete="$3" brmngport="" bripif="" _br1="" _br2="" ips=""
cmclient -v _br1 GETV $brobj.**.[ManagementPort=true].Name
if [ "$allow" = "false" ]; then
local _bridges
cmclient -v _bridges GETO Device.Bridging.Bridge
for _bridges in $_bridges; do
[ "$_bridges" = "$brobj" ] && continue
cmclient -v _br2 GETV "$_bridges".**.[ManagementPort=true].Name
help_iptables -A ForwardDeny.$_br1 -i $_br1 -o $_br2 -j DROP
help_iptables -A ForwardDeny.$_br1 -o $_br1 -i $_br2 -j DROP
cmclient -v brmngport GETO $_bridges.**.[ManagementPort=true]
help_ip_interface_get_first bripif "$brmngport"
cmclient -v ips GETV "$bripif.+.[Enable=true].IPv4Address.IPAddress"
for ip in $ips; do
help_iptables -A InputDeny.$_br1 -i $_br1 --dst $ip -j DROP
done
cmclient -v brmngport GETO $brobj.**.[ManagementPort=true]
help_ip_interface_get_first bripif "$brmngport"
cmclient -v ips GETV "$bripif.+.[Enable=true].IPv4Address.IPAddress"
for ip in $ips; do
help_iptables -A InputDeny.$_br1 -i $_br2 --dst $ip -j DROP
done
done
else
if [ "$delete" = "1" ]; then
help_iptables -F ForwardDeny.$_br1
help_iptables -F InputDeny.$_br1
fi
fi
}
service_do_autoreconf() {
if [ "$newStandard" = "802.1Q-2005" ]; then
local _port_obj _vport_counter _vport _vlan_counter _vlan _vlan_vlanid \
_setm _interface _enable
cmclient -v _port_obj GETO "$this_bridge.Port.[ManagementPort=false]"
for _port_obj in $_port_obj; do
_vport="$this_bridge.VLANPort"
cmclient -v _vport_counter ADD "$_vport"
_vport="$_vport.$_vport_counter"
cmclient SET "$_vport.Port" "$_port_obj"
cmclient -v _vlan_vlanid GETV "$_port_obj.PVID"
cmclient -v _vlan GETO "$this_bridge.VLAN.[VLANID=$_vlan_vlanid]"
if [ -z "$_vlan" ]; then
_vlan="$this_bridge.VLAN"
cmclient -v _vlan_counter ADD "$_vlan"
_vlan="$_vlan.$_vlan_counter"
_setm="${_vlan}.VLANID=${_vlan_vlanid}"
_setm="${_setm}	${_vlan}.Enable=true"
cmclient SETM "$_setm"
fi
_setm="${_vport}.VLAN=${_vlan}"
_setm="${_setm}	${_vport}.Untagged=true"
cmclient -v _enable GETV "$_port_obj.Enable"
if [ "$_enable" = "true" ]; then
cmclient -v _port_lowlayers GETV "$_port_obj.LowerLayers"
help_lowlayer_ifname_get _interface "$_port_lowlayers"
help_del_bridge_port "$newX_ADB_BridgeType" "$_br_name" "$_interface"
fi
_setm="${_setm}	${_vport}.Enable=true"
cmclient SETM "$_setm"
done
else
cmclient DEL "$this_bridge.VLAN"
cmclient DEL "$this_bridge.VLANPort"
SRV_8021D_populate_bridge "add" "$this_bridge" "all"
fi
}
service_stp() {
local _br_name
cmclient -v _br_name GETV "$obj.Port.[ManagementPort=true].[Enable=true].Name"
[ -n "$_br_name" ] || return
help_set_bridge_stp "$newX_ADB_BridgeType" "$_br_name" "$newX_ADB_STP"
}
service_bridge_switch_standard() {
local _br_name _manag_port_obj this_bridge="$obj"
cmclient -v _manag_port_obj GETO "$this_bridge.Port.[ManagementPort=true].[Enable=true]"
[ -z "$_manag_port_obj" ] && return
cmclient -v _br_name GETV "$_manag_port_obj.Name"
[ "$user" = "autoreconf" ] && service_do_autoreconf && return
if [ "$newStandard" = "802.1Q-2005" ]; then
SRV_8021D_populate_bridge "rem" $this_bridge "all"
SRV_8021Q_populate_bridge "add" $this_bridge "all" "all"
else
SRV_8021Q_populate_bridge "rem" $this_bridge "all" "all"
SRV_8021D_populate_bridge "add" $this_bridge "all"
fi
}
checkIfOvsSupported() {
[ ! -x /usr/bin/ovsdb-tool -o ! -x /usr/sbin/ovs-vswitchd -o ! -x /usr/sbin/ovsdb-server ] && return 1
return 0
}
service_config() {
case "$obj" in
Device.Bridging.Bridge.*.VLANPort.*)
service_set_8021Q_vlanport
;;
Device.Bridging.Bridge.*.VLAN.*)
service_set_8021Q_vlan
;;
Device.Bridging.Bridge.*.Port.*)
service_set_8021Q_port
service_check_dad $newName $obj $newStatus
;;
Device.Bridging.Bridge.*)
[ $changedStatus -eq 1 ] && return 0
[ "$changedX_ADB_STP" = "1" ] && service_stp
[ $changedStandard -eq 1 ] && service_bridge_switch_standard
[ $setEnable -eq 1 ] && service_reconf "$obj" "$newStatus" "$newEnable"
[ $changedX_ADB_BridgeType -eq 1 -a $newX_ADB_BridgeType = "OVS" ] && ! checkIfOvsSupported && exit 1
if [ $changedX_ADB_AllowLANRouting -eq 1 ]; then
service_lanrouting "$obj" "$newX_ADB_AllowLANRouting" "1"
fi
[ $setX_ADB_MaxMTUSize -eq 1 -o $changedX_ADB_AutoMTU -eq 1 ] && service_mtu
if [ $changedX_ADB_MulticastIsolation -eq 1 -a "$newX_ADB_BridgeType" != "OVS" ]; then
if [ "$newX_ADB_MulticastIsolation" = "true" ]; then
service_multicast_isolation "start" "wan"
else
service_multicast_isolation "stop" "wan"
fi
fi
if [ $changedX_ADB_MulticastDropIGMPLeaveWhenOtherActive -eq 1 -a "$newX_ADB_BridgeType" != "OVS" ]; then
service_multicast_leaving "$newX_ADB_MulticastDropIGMPLeaveWhenOtherActive"
fi
;;
esac
}
service_delete() {
case "$obj" in
*.VLANPort.*)
is_VLANPort=1
;;
*.VLAN.*)
is_VLAN=1
;;
*.Port.*)
is_port=1
;;
esac
if [ -n "$is_port" ] && [ "$newManagementPort" = "false" ]; then
this_bridge=`help_strextract "$obj" "*.Bridge.*." "."`	# Device.Bridging.Bridge.1
this_port=`help_strextract "$obj" "*.Port.*." "."`	# Device.Bridging.Bridge.1.Port.1
SRV_update_managport_lowlayers "rem" "$this_bridge" "$this_port"
fi
service_get_bridge_standard
if [ "$bridge_standard" = "802.1Q-2005" ]; then
echo "### $AH_NAME: 802.1Q Bridge DEL operation ###"
fi
service_delete_8021Q
cmclient -v br1 GETV $obj.**.[ManagementPort=true].Name
if [ -n "$br1" ]; then
help_iptables -F ForwardDeny.$br1
help_iptables -D ForwardDeny -j ForwardDeny.$br1
help_iptables -X ForwardDeny.$br1
help_iptables -F InputDeny.$br1
help_iptables -D InputDeny -j InputDeny.$br1
help_iptables -X InputDeny.$br1
fi
}
service_add() {
case "$obj" in
*.VLANPort.*)
is_VLANPort=1
;;
*.VLAN.*)
is_VLAN=1
;;
*.Port.*)
is_port=1
;;
esac
if [ -n "$is_port" ]; then
this_bridge=`help_strextract "$obj" "*.Bridge.*." "."`	# Device.Bridging.Bridge.1
this_port=`help_strextract "$obj" "*.Port.*." "."`	# Device.Bridging.Bridge.1.Port.1
SRV_update_managport_lowlayers "add" "$this_bridge" "$this_port"
fi
service_get_bridge_standard
if [ "$bridge_standard" = "802.1Q-2005" ]; then
return
fi
num=${obj##*.}
if [ "$num" = 2 ]; then
cmclient -v br1 GETV "$this_bridge".Port.1.Name
if [ -n "$br1" ]; then 
help_iptables -N ForwardDeny.$br1
help_iptables -A ForwardDeny -j ForwardDeny.$br1
help_iptables -N InputDeny.$br1
help_iptables -A InputDeny -j InputDeny.$br1
fi
fi
}
service_get_bridge_standard() {
local bridge_obj=`help_strextract "$obj" "*.Bridge.*." "."`
cmclient -v bridge_standard GETV "$bridge_obj.Standard"
}
finish_blank_config() {
local bridge all_bridges regular_port all_regular_ports
cmclient -v all_bridges GETO Device.Bridging.Bridge
for bridge in $all_bridges; do
cmclient -v all_regular_ports GETO $bridge.Port.[ManagementPort=false]
for regular_port in $all_regular_ports; do
SRV_update_managport_lowlayers "add" "$bridge" "$regular_port" > /dev/null
done
done
}
if [ $# -eq 1 ] && [ "$1" = "init" ]; then
cmclient -v _manports GETO Device.Bridging.Bridge.[Enable=true].*.Port.[ManagementPort=true].[Enable=true]
for _manport in $_manports; do
_iface_list=""
_br_obj=${_manport%%.Port*}
cmclient -v _br_name GETV "${_manport}.Name"
cmclient -v _br_stp GETV  "${_br_obj}.X_ADB_STP"
cmclient -v _br_standard GETV  "${_br_obj}.Standard"
cmclient -v _br_type GETV  "${_br_obj}.X_ADB_BridgeType"
cmclient -v _br_allowlanrouting GETV "${_br_obj}.X_ADB_AllowLANRouting"
cmclient -v _br_multicastisolation GETV  "${_br_obj}.X_ADB_MulticastIsolation"
cmclient -v _br_multicast_leave GETV "${_br_obj}.X_ADB_MulticastDropIGMPLeaveWhenOtherActive"
cmclient -v _br_hasfakeports  GETO "${_br_obj}.Port.[X_ADB_FakePort=true]"
help_iptables -N ForwardDeny.$_br_name
help_iptables -A ForwardDeny -j ForwardDeny.$_br_name
help_iptables -N InputDeny.$_br_name
help_iptables -A InputDeny -j InputDeny.$_br_name
if [ "$_br_standard" != "802.1Q-2005" ] && [ -z "$_br_hasfakeports" ]; then
help_add_bridge "$_br_type" "$_br_name"
cmclient -v _ports GETO ${_br_obj}.Port.*.[ManagementPort=false].[Enable=true]
for _port in $_ports; do
cmclient -v _iface GETV ${_port}.Name
[ -z "$_iface" ] && help_lowlayer_ifname_get _iface "$_port" && \
cmclient SET ${_port}.Name "$_iface"
if [ -n "$_iface" ]; then
if [ -d /sys/class/net/"$_iface" ]; then
help_add_bridge_port "$_br_type" "$_br_name" "$_iface" "${_port##$_br_obj.Port.}"
_iface_list="${_iface_list}-(${_iface})-"
else
[ "$_br_type" = "OVS" ] && help_add_bridge_port "$_br_type" "$_br_name" "$_iface" "${_port##$_br_obj.Port.}"
_iface_list="${_iface_list}-(${_iface}*)-"
fi
fi
if is_wan_intf $_port; then
ebtables -A IGMPlan -o $_iface -j RETURN
ebtables -A IGMPlan -i $_iface -j RETURN
fi
done
read _br_mac < /sys/class/net/"$_br_name"/address
_br_mac=`help_tr ":" "" "$_br_mac"`
echo "$_br_mac 0 1 100 1" > /proc/hwswitch/default/arl
[ "$_br_type" = "OVS" ] && ethswctl -c multiport -p 0 -m ffffffffffff
else
cmclient -v _objs GETV ${_br_obj}.VLAN.[Enable=true].VLANID
for vlan_obj in $_objs; do
_brnum=$((${_br_obj##*Bridge.}-1))
_vbridge="$BRIDGE_PREFIX$_brnum$VLAN_PREFIX$vlan_obj"
SRV_8021Q_create_vlanbridge "add" "$_vbridge" "$_br_type" ""
done
cmclient -v _objs GETO ${_br_obj}.VLANPort.[Enable=true].[Untagged=false]
for vport_obj in $_objs; do
cmclient -u "init" SET "$vport_obj.Enable" "true"
done
cmclient -u "init" SET "${_manport}.Enable" "true"
_iface_list="- VLAN or Filters enabled - slow bridge boot"
fi
service_lanrouting "${_br_obj}" "$_br_allowlanrouting"
if [ "$_br_multicastisolation" = "true" -a "$_br_type" != "OVS" ]; then
obj="$_br_obj"
service_multicast_isolation "start" "wan"
fi
if [ "$_br_multicast_leave" = "true" -a "$_br_type" != "OVS" ]; then
obj="$_br_obj"
service_multicast_leaving "true"
fi
help_lowlayer_ifname_get _iface "$_manport"
help_ipv6_reconf_iface "$_iface"
echo "==[$_br_name]== $_br_standard  $_iface_list" > /dev/console
[ $_br_stp = "true" ] && help_set_bridge_stp "$_br_type" "$_br_name" "true"
cmclient SET ${_manport}.Status "Up"
cmclient SET -u "${AH_NAME}${_br_obj}" $_br_obj.Status "Enabled"
ifconfig $_br_name up
done
fi
if [ $# -eq 1 ] && [ "$1" = "refreshlanrouting" ]; then
cmclient -v _bridges GETO Device.Bridging.Bridge
for b in $_bridges; do
cmclient -v s GETV $b.X_ADB_AllowLANRouting
if [ "$s" = "false" ]; then
service_lanrouting "$b" "true" "1"
service_lanrouting "$b" "false"
fi
done
exit 0
fi
if [ $# -eq 1 ] && [ "$1" = "finishblank" ]; then
finish_blank_config
exit 0
fi
case "$op" in
a)
service_add
;;
d)
service_delete
;;
g)
for arg; do
service_get "$obj.$arg"
done
;;
s)
service_config
;;
esac
exit 0
