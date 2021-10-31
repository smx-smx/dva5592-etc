#!/bin/sh
AH_NAME="PTMLink"
. /etc/ah/helper_dsl.sh
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_status.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/helper_stats.sh
. /etc/ah/target.sh
ifname=$newName
xtm_lowlayer=""
xtm_portId=""
xtm_linktype=""
xtm_config_conn_state() {
help_get_ptm_port_id xtm_portId "$obj"
xtm_connection_state "$xtm_portId.1" $1
}
xtm_config_conn_add() {
help_get_ptm_port_id xtm_portId "$obj"
if [ "$1" = "add" ]; then
xtm_add_connection "$xtm_portId.1"
else
xtm_delete_queue $xtm_portId.1 0
xtm_delete_connection "$xtm_portId.1"
fi
if [ "$1" = "add" ]; then
xtm_add_queue $xtm_portId.1 400 0 rr 10 0 0 0
fi
}
xtm_config_conn_do_add() {
local cmd="$1"
xtm_tdte_index="1"
xtm_config_conn_add "$cmd"
}
xtm_config_conn_netdev() {
local _ifname="$2" _obj="$3" _mtu="$4" _portID mac
help_get_ptm_port_id _portID "$obj"
[ -z "$_mtu" ] && _mtu=0
if [ "$1" = "create" ]; then
_mac=`help_get_ptm_mac_address ${_obj}`
xtm_create_network_device "${_portID}.1" "$_ifname"
else
tc qdisc del dev "$_ifname" root fbd
xtm_delete_network_device "${_portID}.1"
fi
if [ "$1" = "create" ]; then
echo "### $AH_NAME: Executing <ifconfig $_ifname hw ether $_mac> ###"
ifconfig "$_ifname" hw ether "$_mac"
help_serialize_unlock "get_mac_lock"
[ $_mtu -gt 0 ] && ip link set "$_ifname" mtu "$_mtu"
tc qdisc add dev "$_ifname" root fbd
fi
}
check_enc() {
local _path=$1 _chan=$2 _ifname=$3 tmp
case "$_chan" in
Device.DSL.BondingGroup.*)
cmclient -v _chan GETV "$_chan.LowerLayers"
;;
esac
set -f
IFS=','
set -- $_chan
unset IFS
set +f
for _chan; do
cmclient -v tmp GETV "$_chan.LinkEncapsulationUsed"
case "$tmp" in
*"ATM")
exit 0
;;
esac
done
}
service_align_upper_layers() {
local _path="$1" _enable="$2" eth_link=""
align_upper_layers "$_path" "$_enable" "Device.Bridging.Bridge.*.Port"
cmclient -v eth_link GETO "Device.Ethernet.Link.[LowerLayers=$_path]"
[ -n "$eth_link" ] && \
align_upper_layers "$eth_link" "$_enable" "Device.Ethernet.VLANTermination"
}
service_do_reconf() {
local _path="$1" _status="$2" _ifname="$3" _enable="$4" _mtu="$5"
local itf itf_list
if [ "$changedEnable" = "1" ]; then
if [ "$newEnable" = "false" ]; then
xtm_config_conn_state "disable"
elif [ "$newEnable" = "true" ]; then
xtm_config_conn_state "enable"
fi
fi
if [ "$_enable" = "true" -a "$_status" = "Up" ]; then
for atmdev in /sys/class/net/atm*; do
[ -d "$atmdev" ] || continue
echo "### $AH_NAME: Executing <ip link set ${atmdev##*/} down>"
xdsl_set_link "${atmdev##*/}" down
done
if ! [ -d "/sys/class/net/$_ifname" ]; then
xtm_config_conn_do_add "add"
xtm_config_conn_state "enable"
xtm_config_conn_netdev "create" "$_ifname" "$_path" "$_mtu"
help_ipv6_reconf_iface "$_ifname"
fi
xtm_created=1
fi
}
service_status_reconf() {
local _path="$1" _status="$2" _enable="$3" _ifname="$4" _lowlayer_status="$5"
local _mtu="$6" new_status
xtm_created=0
[ "$_lowlayer_status" = "Up" -a "$_enable" = "true" ] && \
check_enc $_path $obj $_ifname
help_get_status_from_lowerlayers new_status "$obj" "$_enable" "$_lowlayer_status" true
service_do_reconf "$_path" "$new_status" "$_ifname" "$_enable" "$_mtu"
if [ "$_enable" = "true" -a "$xtm_created" -eq 1 ]; then
service_align_upper_layers "$_path" "$_enable"
fi
if [ "$new_status" = "Up" ]; then
xdsl_set_link "$_ifname" up
elif [ "$new_status" = "LowerLayerDown" ]; then
xdsl_set_link "$_ifname" down
fi
cmclient SET -u "${AH_NAME}${_path}" "$_path.Status" "$new_status"
}
service_reconf() {
local _path="$1" _status="$2" _enable="$3" _ifname="$4" _lowlayer="$5" \
_mtu="$6" new_status
help_get_status_from_lowerlayers new_status $_path "$_enable" "$_lowlayer"
[ "$_enable" = "false" ] && service_align_upper_layers "$_path" "$_enable"
service_do_reconf "$_path" "$new_status" "$_ifname" "$_enable" "$_mtu"
[ "$_enable" = "true" ] && \
service_align_upper_layers "$_path" "$_enable"
[ "$new_status" != "$_status" ] && \
cmclient SET -u "${AH_NAME}${_path}" "$_path.Status" "$new_status"
[ "$(ip link show dev $_ifname up)" = "" ] && _old_status="true" || _old_status="false"
[ "$_enable" = "$_old_status" -a "$_enable" = "true" ] && help_if_link_change "$_ifname" "Up" "$AH_NAME"
}
service_get() {
local object="$1" param="$2" buf=""
case "$object" in
"InternetGatewayDevice"* )
object="${object%%.Stats}"
cmclient -v object GETV "$object.X_ADB_TR181Name"
case "$param" in
"FramesReceived") param="PacketsReceived"	;;
"FramesSent") param="PacketsSent" ;;
esac
;;
*"Stats" )
object="${object%%.Stats}"
;;
esac
case "$param" in
LastChange)
. /etc/ah/helper_lastChange.sh
help_lastChange_get "$obj"
;;
*)
local currentVal parVal
cmclient -v ifname GETV "$object.Name"
if [ -n "$ifname" ]; then
help_get_base_stats_core "$obj.$param" "$ifname" currentVal
eval "parVal=\$new$2"
if [ ${parVal:=0} -le $currentVal ]; then
echo $((currentVal-parVal))
else
echo $(((1<<32) - (parVal - currentVal)))
fi
else
echo ""
fi
;;
esac
}
service_config() {
local status_val enable_val currlayer_ifname mtu _name
case "$obj" in
Device.PTM.Link.*)
if [ "$setX_ADB_Reset" = "1" ]; then
cmclient -v _name GETV "${obj%.Stats}.Name"
help_reset_stats $obj
fi
if [ "$changedStatus" = "1" ]; then
return 0
fi
if [ "$changedEnable" = "1" ]; then
[ "$newEnable" = "true" ] && check_enc "$obj" "$newLowerLayers" "$ifname"
service_reconf "$obj" "$newStatus" "$newEnable" "$ifname" "$newLowerLayers" "$newX_ADB_MTU"
fi
;;
*)
cmclient -v lower_layers GETO "Device.PTM.Link.*.[LowerLayers=$obj]"
for lower_layers in $lower_layers; do
cmclient -v status_val GETV "$lower_layers.Status"
cmclient -v enable_val GETV "$lower_layers.Enable"
cmclient -v currlayer_ifname GETV "$lower_layers.Name"
cmclient -v mtu GETV "$lower_layers.X_ADB_MTU"
service_status_reconf "$lower_layers" "$status_val" "$enable_val" "$currlayer_ifname" "$newStatus" "$mtu"
done
;;
esac
}
service_delete() {
help_xtm_link_down "$oldName"
xtm_config_conn_netdev "delete" "$oldName"
xtm_config_conn_state "disable"
xtm_config_conn_add "delete"
}
delete_netdevs()
{
local obj objs chan=$1 _name
cmclient -v objs GETO "Device.PTM.Link.*.[LowerLayers=$chan]"
for obj in $objs; do
cmclient -v _name GETV "$obj.Name"
cmclient SETE "$obj".Status Error
help_xtm_link_down "$_name"
xtm_config_conn_netdev "delete" "$_name" $obj
xtm_config_conn_state "disable"
xtm_config_conn_add "delete"
done
exit 0
}
[ $# -eq 2 -a "$1" = "del" ] && delete_netdevs $2
case "$op" in
d)
service_delete
;;
g)
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
;;
s)
service_config
;;
esac
exit 0
