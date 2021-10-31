#!/bin/sh
AH_NAME="IPIf"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
if [ "$user" = "InterfaceMonitor" ]; then
exit 0
fi
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_status.sh
. /etc/ah/helper_mtu.sh
. /etc/ah/IPv6_helper_functions.sh
if [ -x /etc/ah/helper_loopback.sh ]; then
. /etc/ah/helper_loopback.sh
fi
routing_create_device_rule() {
table_idx=`get_dev_rule_table $1`
rt_tables=`ip rule`
is_there=`help_strstr "$rt_tables" "lookup $table_idx"`
if [ -z "$is_there" ]; then
mark_dev=`get_dev_mark $1`
ip rule add fwmark "$mark_dev"/0xFF00 table "$table_idx" pref 30000 iif lo
fi
}
service_disable_def_route() {
local _path="$1" _router="$2" _default="$3" objs ipsecProfile
if [ "$_default" = "false" ]; then
cmclient -v objs GETO "$_router.IPv4Forwarding.*.[DestIPAddress=].[Interface=$_path].[Enable=true]"
for _route in $objs; do
cmclient SET "$_route.Enable" "false"
done
cmclient -v objs GETO "$_router.IPv6Forwarding.*.[DestIPPrefix=].[Interface=$_path].[Enable=true]"
for _route in $objs; do
cmclient SET "$_route.Enable" "false"
done
else
cmclient -v objs GETO "Device.IP.Interface.[X_ADB_DefaultRoute=true]"
for _ip in $objs; do
[ "$_ip" = "$obj" ] && continue
cmclient SET "$_ip.X_ADB_DefaultRoute" "false"
done
cmclient SET "$_router.IPv4Forwarding.*.[DestIPAddress=].[Interface=$_path].Enable" "true"
cmclient SET "$_router.IPv6Forwarding.*.[DestIPPrefix=].[Interface=$_path].Enable" "true"
fi
if [ -s /etc/ah/helper_ipsec.sh ]; then
cmclient -v ipsecProfile GETO Device.IPsec.Profile.[X_ADB_LocalEndpoint=]
[ "$changedX_ADB_DefaultRoute" = "1" -a ${#ipsecProfile} -ne 0 ] && \
cmclient SET Device.IPsec.X_ADB_Reset true
fi
}
service_conf_dhcp_route() {
local _path="$1" _enable="$2"
cmclient SET "Device.Routing.Router.IPv4Forwarding.[Interface=$_path].[StaticRoute=false].[Origin=DHCPv4].[DestIPAddress!].[Enable!$_enable].Enable" "$_enable"
}
update_igmproxy_upstreaminterface()
{
local _ifobj=$1
local _iftype=$2
local _ifstatus=$3
local _ifupstr=$4
! help_is_in_list "$_iftype" "Iptv" && return
! help_is_in_list "$_ifupstr" "true" && return
cmclient -v _autoconf GETV Device.Services.X_ADB_IGMPProxy.UpstreamInterfaceAutoConfig
if [ "$_autoconf" = "true" ]; then
cmclient -v upif GETV Device.Services.X_ADB_IGMPProxy.UpstreamInterfaces
case "$_ifstatus" in
"true" | "enable" | "Up" )
if ! help_is_in_list "$upif" "$_ifobj"; then
[ -n "$upif" ] && upif="$upif,"
upif="$upif""$_ifobj"
cmclient SET "Device.Services.X_ADB_IGMPProxy.UpstreamInterfaces" "$upif"
fi
;;
* )
if help_is_in_list "$upif" "$_ifobj"; then
IFS=','
set -- $upif
unset IFS
upif=
for ui; do [ "$ui" != "$_ifobj" ] && upif=${upif:+$upif,}$ui; done
cmclient SET "Device.Services.X_ADB_IGMPProxy.UpstreamInterfaces" "$upif"
fi
;;
esac
fi
}
update_voice_outboundinterface()
{
local _ifobj=$1
local _iftype=$2
local _ifstatus=$3
local objs
local vifs
! help_is_in_list "$_iftype" "Voip" && return
cmclient -v objs GETO "Device.Services.VoiceService.*.[X_ADB_OutboundInterfaceAutoConfig=true]"
for vs in $objs; do
case "$_ifstatus" in
"true" | "enable" | "Up" )
cmclient SET "$vs.X_ADB_OutboundInterface" "$_ifobj"
;;
* )
cmclient -v voiceif GETV "$vs.X_ADB_OutboundInterface"
if [ "$voiceif" = "$_ifobj" ]; then
newvoiceif=""
cmclient -v vifs "GETO Device.IP.Interface.*.[X_ADB_ConnectionType>Voip].[Status=Up]"
for vif in $vifs; do
if [ "$vif" != "$voiceif" ]; then
newvoiceif="$vif"
break
fi
done
cmclient SET "$vs.X_ADB_OutboundInterface" "$newvoiceif"
fi
;;
esac
done
}
update_upnp_externalif() {
local _ifobj=$1 _iftype=$2 _ifstatus=$3 _autoconf
[ -e /etc/ah/UPnP.sh ] || return
help_is_in_list "$_iftype" "Data" || return
cmclient -v _autoconf GETV Device.UPnP.Device.X_ADB_AutoExternalInterface
[ "$_autoconf" = "true" ] || return
case "$_ifstatus" in
"true" | "enable" | "Up" )
cmclient SET "Device.UPnP.Device.X_ADB_ExternalInterface" "$_ifobj"
;;
* )
cmclient -v extif GETV "Device.UPnP.Device.X_ADB_ExternalInterface"
if [ "$extif" = "$_ifobj" ]; then
local vifs
newextif=""
cmclient -v vifs "GETO Device.IP.Interface.*.[X_ADB_ConnectionType>Data].[Status=Up]"
for vif in $vifs; do
if [ "$vif" != "$extif" ]; then
newextif="$vif"
break
fi
done
cmclient SET "Device.UPnP.Device.X_ADB_ExternalInterface" "$newextif"
fi
;;
esac
}
update_port_mapping() {
local _ifobj=$1
local _iftype=$2
local _ifstatus=$3
local pmobjs
case "$_ifstatus" in
"true" | "enable" | "Up" )
cmclient -v pmobjs GETO "Device.NAT.PortMapping.+.[X_ADB_WanConnectionType<$_iftype]"
for pmobj in $pmobjs; do
cmclient -v wan_conn_type GETV "$pmobj.X_ADB_WanConnectionType"
if [ "$wan_conn_type" != "" ]; then
cmclient SET "$pmobj".Interface "$_ifobj"
fi
done
;;
* )
cmclient -v pmobjs GETO "Device.NAT.PortMapping.+.[Interface=$_ifobj].[X_ADB_WanConnectionType<$_iftype]"
for pmobj in $pmobjs; do
cmclient -v wan_conn_type GETV "$pmobj.X_ADB_WanConnectionType"
if [ "$wan_conn_type" != "" ]; then
cmclient SET "$pmobj".Interface ""
fi
done
;;
esac
}
service_do_reconf() {
local _path="$1" _ifname="$2" _enable="$3" tmp objs ret=0 _dmz_enable _dmz_qos
cmclient -u "$AH_NAME" SET "$_path.IPv4Address.[AddressingType=Static].[Enable=true].Enable" "true"
[ "${_ifname}" != "${_ifname#ppp}" ] && dhcp_obj="" || \
cmclient -v dhcp_obj GETO "Device.DHCPv4.Client.[Interface=$_path]"
[ ${#dhcp_obj} -ne 0 ] && cmclient -v dhcp_enable GETV "$dhcp_obj.Enable" || dhcp_enable="false"
[ "$dhcp_enable" = "true" -a "$_enable" = "true" ] && cmclient SET "$dhcp_obj.Enable" "true"
if [ "$_enable" = "false" ]; then
cmclient -v objs GETO "$_path.IPv4Address.[AddressingType=IPCP]"
for ipv4_dhcp in $objs; do
echo "### $AH_NAME: DEL <$ipv4_dhcp>"
cmclient DEL "$ipv4_dhcp"
done
fi
if [ "$dhcp_enable" = "true" -a "$_enable" = "false" ]; then
read pid < /tmp/dhcpc_"$dhcp_obj"
if [ ${#pid} -ne 0 ]; then
kill "$pid"
rm /tmp/dhcpc_"$dhcp_obj"
fi
fi
if [ "$dhcp_enable" = "false" -o "$_enable" = "false" ]; then
cmclient -v router_path GETV "$_path.Router"
if [ ${#router_path} -ne 0 -a "$_enable" = "false" -a "$dhcp_enable" = "false" ]; then
cmclient -v objs GETO "$router_path.IPv4Forwarding.*.[Interface=$_path].[StaticRoute=false]"
for dyn_route in $objs; do
echo "### $AH_NAME: DEL <$dyn_route>"
cmclient DEL "$dyn_route"
done
fi
if [ ${#router_path} -ne 0 ]; then
cmclient -u "$AH_NAME" SET "$router_path.IPv4Forwarding.*.[Interface=$_path].[StaticRoute=true].[Enable=true].Enable" "true"
fi
fi
if [ "$dhcp_enable" = "false" -a -z "$is_ppp" ]; then
if [ -f /etc/ah/VoIPNetwork.sh  ]; then
/etc/ah/VoIPNetwork.sh u $_path &
fi
fi
ret=$?
cmclient -v _type GETV "$_path.X_ADB_ConnectionType"
cmclient -v _upstr GETV "$_path.X_ADB_Upstream"
update_voice_outboundinterface "$_path" "$_type" "$_enable"
update_igmproxy_upstreaminterface "$_path" "$_type" "$_enable" "$_upstr"
update_upnp_externalif "$_path" "$_type" "$_enable"
update_port_mapping "$_path" "$_type" "$_enable"
cmclient -u refresh SET "Device.NAT.InterfaceSetting.[Interface=$_path].[Enable=true].Enable" "true"
return $ret
}
check_link_up() {
local layer="$1"
local lower=""
case "$layer" in
*.ATM.Link.*|*.PTM.Link.*|*.Ethernet.Link.*|*.X_ADB_MobileModem.Interface.*)
cmclient -v lower GETV $layer.Status
[ "$lower" = "Up" ] && return 0
;;
esac
cmclient -v lower GETV $layer.LowerLayers
lower=$(help_tr "," " " "$lower")
for layer in $lower; do
check_link_up "$layer" && return 0
done
return 1
}
uplinked_list=""
get_uplinked_list() {
local list="$1"
local item=""
uplinked_list=""
for item in $list; do
check_link_up "$item" && uplinked_list="$uplinked_list $item"
done
uplinked_list=`expr "$uplinked_list" : ' \?\(.*\)'`
[ -n "$uplinked_list" ] && return 0 || return 1
}
is_lower_layer() {
local layer layer1="$1" layer2="$2"
cmclient -v lower GETV $layer2.LowerLayers
IFS=','
set -- $lower
unset IFS
for layer; do
[ "$layer" = "$layer1" ] && return 0
is_lower_layer "$layer1" "$layer" && return 0
done
return 1
}
top_in_stack=""
get_top_in_stack() {
local list="$1"
local item1=""
local item2=""
top_in_stack=""
[ -z "$list" ] && return 1
set $list
[ $# -eq 1 ] && { top_in_stack="$list" ; return 0 ; }
for item1 in $list; do
for item2 in $list; do
[ "$item1" = "$item2" ] && continue
is_lower_layer "$item1" "$item2" && continue 2
done
top_in_stack="$item1"
return 0
done
return 1
}
main_wan_interface=""
get_main_wan_interface() {
local tmp=""
main_wan_interface=""
cmclient -v tmp GETO Device.IP.Interface.[X_ADB_Upstream=true].[X_ADB_DefaultRoute=true].[Status=Up]
if [ ${#tmp} -ne 0 ]; then
get_top_in_stack "$tmp"
main_wan_interface="$top_in_stack"
return 0
fi
cmclient -v tmp GETO Device.IP.Interface.[X_ADB_Upstream=true].[X_ADB_DefaultRoute=true]
if [ ${#tmp} -ne 0 ]; then
set $tmp
[ $# -eq 1 ] && { main_wan_interface="$1" ; return 0 ; }
main_wan_interface="$1"
get_uplinked_list "$tmp"
if [ -n "$uplinked_list" ]; then
get_top_in_stack "$uplinked_list"
main_wan_interface="$top_in_stack"
fi
return 0
fi
cmclient -v tmp GETO Device.IP.Interface.[X_ADB_Upstream=true]
if [ ${#tmp} -ne 0 ]; then
set $tmp
[ $# -eq 1 ] && { main_wan_interface="$1" ; return 0 ; }
main_wan_interface="$1"
get_uplinked_list "$tmp"
if [ -n "$uplinked_list" ]; then
get_top_in_stack "$uplinked_list"
main_wan_interface="$top_in_stack"
fi
return 0
fi
return 1
}
service_get() {
local obj="$1" par="$2" p="" ll
case "$par" in
"X_ADB_CurrentMTUSize" )
if [ -n "$ifname" -a -d /sys/class/net/"$ifname" ]; then
read p < /sys/class/net/"$ifname"/mtu
else
cmclient -v p GETV $obj.X_ADB_AutoMTU
if [ "$p" = true ]; then
case "$obj" in
*"Bridging"*)
ll="$obj".Port
;;
*) help_active_lowlayer ll "$obj" ;;
esac
help_get_default_mtu p $ll
else
cmclient -v p GETV $obj.MaxMTUSize
fi
fi
echo $p
;;
"X_ADB_MainWANInterface" )
get_main_wan_interface
echo $main_wan_interface
;;
LastChange)
. /etc/ah/helper_lastChange.sh
help_lastChange_get "$obj"
;;
*)
[ -n "$ifname" ] && help_get_base_stats "$obj.$par" "$ifname"
;;
esac
}
service_rp_filter_reconf() {
local _path="$1" lower="" old_rp_filter if_name rp_filter
if [ "$newX_ADB_RPFilter" = "-1" ]; then
read rp_filter < /proc/sys/net/ipv4/conf/all/rp_filter
else
rp_filter="$newX_ADB_RPFilter"
fi
cmclient -v lower GETV $_path.LowerLayers
IFS=","
for lower in $lower; do
cmclient -v if_name GETV $lower.Name
if [ -f "/proc/sys/net/ipv4/conf/$if_name/rp_filter" ]; then
read old_rp_filter < /proc/sys/net/ipv4/conf/$if_name/rp_filter
[ "$old_rp_filter" != "$rp_filter" ] && echo "$rp_filter" > /proc/sys/net/ipv4/conf/$if_name/rp_filter
fi
done
unset IFS
}
service_status_reconf() {
local _path="$1" _enable="$2" _ifname="$3" lowlayer_status="$4" is_ppp="$5" trigger="$6" connstatus="$7" ppp_enable="$8"
if [ -n "$is_ppp" ]; then
if [ "$_enable" = "true" ]; then
if [ "$ppp_enable" = "true" ]; then
case "$lowlayer_status" in
"Up")
if [ "$connstatus" = "Connected" ]; then
new_status="Up"
elif [ "$trigger" = "OnDemand" ]; then
new_status="Dormant"
else
new_status="LowerLayerDown"
fi
;;
"Down" | "Unknown" | "NotPresent" | "LowerLayerDown" | "Error" )
new_status="LowerLayerDown"
;;
"Dormant")
new_status="Dormant"
;;
esac
else
new_status="LowerLayerDown"
fi
else
new_status="Down"
fi
elif [ "$newLoopback" = "true" ]; then
if [ -x /etc/ah/helper_loopback.sh ]; then
[ "$_enable" = "true" ] && new_status="Up" || new_status="Down"
else
new_status="NotPresent"
fi
else
help_get_status_from_lowerlayers new_status "$_path" "$_enable"
fi
if [ "$new_status" = "Dormant" -o "$new_status" = "Up" ]; then
[ "$newLoopback" = "false" ] && service_rp_filter_reconf "$_path"
fi
cmclient SET "$_path.Status" "$new_status"
}
service_reconf() {
local _path="$1"
local _status="$2"
local _enable="$3"
local _ifname="$4"
local _lowlayer="$5"
local _is_ppp="$6"
local lowlayer_enable
if [ -n "$_is_ppp" ]; then
if [ "$_enable" = "true" ]; then
cmclient -v lowlayer_enable GETV "$_lowlayer.Enable"
if [ "$lowlayer_enable" = "true" ]; then
local lowlayer_status
cmclient -v lowlayer_status GETV "$_lowlayer.Status"
case "$lowlayer_status" in
"Up")
local conn_status
cmclient -v conn_status GETV "$_lowlayer.ConnectionStatus"
if [ "$conn_status" = "Connected" ]; then
new_status="Up"
else
cmclient -v trigger GETV "$_lowlayer.ConnectionTrigger"
if [ "$trigger" = "OnDemand" ]; then
new_status="Dormant"
else
new_status="LowerLayerDown"
fi
fi
;;
"Down" | "Unknown" | "NotPresent" | "LowerLayerDown" | "Error" )
new_status="LowerLayerDown"
;;
"Dormant")
new_status="Dormant"
;;
esac
else
new_status="LowerLayerDown"
fi
else
new_status="Down"
fi
elif [ "$newLoopback" = "true" ]; then
if [ -x /etc/ah/helper_loopback.sh ]; then
[ "$_enable" = "true" ] && new_status="Up" || new_status="Down"
else
new_status="NotPresent"
fi
else
help_get_status_from_lowerlayers new_status "$_path" "$_enable" "$_lowlayer"
fi
if [ "$new_status" != "$_status" ]; then
cmclient SET "$_path.Status" "$new_status"
fi
}
ipv6_service_do_reconf() {
local _path="$1" _ifname="$2" _enable="$3" neigh_enable='' ipv6_enable glob_ipv6_enable glob_neigh_enable dhcp_obj dhcp_enable
cmclient -v ipv6_enable GETV "$_path.IPv6Enable"
cmclient -v glob_ipv6_enable GETV "Device.IP.IPv6Enable"
if [ "$ipv6_enable" = "true" -a "$glob_ipv6_enable" = "true" ]; then
ipv6_proc_enable "$ipv6_enable" "$_ifname"
cmclient SET "$_path.IPv6Prefix.[Origin=Static].[Enable=true].Enable" "true"
cmclient DEL "$_path.IPv6Prefix.[Origin=RouterAdvertisement].[Enable=true]"
cmclient SET "$_path.[ULAEnable=true].ULAEnable" "true"
if [ -f /etc/ah/IPv6_helper_swisscom.sh -a "$_enable" = "true" -a "$newX_ADB_Upstream" != "false" ]; then
. /etc/ah/IPv6_helper_swisscom.sh
help_ipv6n_update_dflt_route "$_path"
fi
cmclient -u "$AH_NAME" SET "Device.Routing.Router.*.IPv6Forwarding.*.[Interface=$_path].[Origin=Static].[Enable=true].Enable" "true"
cmclient -v dhcp_obj GETO "Device.DHCPv6.Client.[Interface=$_path]"
[ ${#dhcp_obj} -ne 0 ] && cmclient -v dhcp_enable GETV "$dhcp_obj.Enable" || dhcp_enable="false"
[ "$dhcp_enable" = "true" -a "$_enable" = "true" ] && cmclient SET "$dhcp_obj.Enable" "true"
if [ "$dhcp_enable" = "true" -a "$_enable" = "false" ]; then
env obj="$dhcp_obj" op="stop" ifname="$_ifname" /etc/ah/DHCPv6Client.sh
fi
if [ -f /etc/ah/IPv6_helper_swisscom.sh -a "$_enable" = "false" ]; then
cmclient -v iface GETO "$_path.[X_ADB_Upstream=true].[IPv6Enable=true]"
if [ ${#iface} -ne 0 ]; then
. /etc/ah/IPv6_helper_swisscom.sh
help_swc_ipv6_deprecate_wan_itf "$iface"
fi
fi
fi
cmclient -v glob_neigh_enable GETV "Device.NeighborDiscovery.Enable"
[ "$glob_neigh_enable" = "true" ] && \
cmclient -v neigh_enable GETV "Device.NeighborDiscovery.InterfaceSetting.[Interface=$_path].Enable"
[ ${#neigh_enable} -eq 0 ] && ipv6_neigh_proc_enable "false" "$_ifname" || \
cmclient SET "Device.NeighborDiscovery.InterfaceSetting.[Interface=$_path].Enable" "$neigh_enable"
}
service_config() {
case "$obj" in
Device.IP.Interface.*.Stats)
if [ "$setX_ADB_Reset" = "1" ]; then
local lowlayer_obj activelowlayer_obj lowlayer_ifname is_ppp=""
cmclient -v lowlayer_obj GETV "${obj%.Stats}".LowerLayers
cmclient -v activelowlayer_obj GETV "${obj%.Stats}".X_ADB_ActiveLowerLayer
help_lowlayer_ifname_get lowlayer_ifname "$lowlayer_obj" $activelowlayer_obj
case "$lowlayer_ifname" in
[ap]tm)
xtmctl reset_stats --intf "$lowlayer_ifname"
;;
eth*)
ethswctl -c test -t 2
;;
wl*)
. /etc/ah/target.sh
wifiradio_reset_stats "$lowlayer_ifname"
;;
*)
echo "$lowlayer_ifname" > /proc/net/reset_stats
;;
esac
fi
;;
"Device.IP.Interface"*)
local lowlayer_ifname lowlayer maxMTU
[ "$newType" = "Loopback" -a $setLowerLayers -eq 1 ] && exit 0
if [ $changedLoopback -eq 1 ]; then
[ -x /etc/ah/helper_loopback.sh ] && ip_loopback_set "$obj" "$newLoopback"
fi
if [ "$newLoopback" = "true" ]; then
[ -x /etc/ah/helper_loopback.sh ] && ip_loopback_get_if_name lowlayer_ifname || exit 0
else
help_lowlayer_ifname_get lowlayer_ifname "$newLowerLayers" $newX_ADB_ActiveLowerLayer
fi
if [ "$user" = "InterfaceStack" -a "$setEnable" = "1" ]; then
local lowlayer_status _status  ppp_connstatus ppp_trigger ppp_enable
cmclient -v lowlayer_status GETV "$newX_ADB_ActiveLowerLayer.Status"
case "$newX_ADB_ActiveLowerLayer" in
"Device.PPP.Interface"*)
cmclient -v ppp_connstatus GETV "$newX_ADB_ActiveLowerLayer.ConnectionStatus"
cmclient -v ppp_trigger GETV "$newX_ADB_ActiveLowerLayer.ConnectionTrigger"
cmclient -v ppp_enable GETV "$newX_ADB_ActiveLowerLayer.Enable"
service_status_reconf "$obj" "$newEnable" "$lowlayer_ifname" "$lowlayer_status" "true" "$ppp_trigger" "$ppp_connstatus" "$ppp_enable"
;;
*)
service_status_reconf "$obj" "$newEnable" "$lowlayer_ifname" "$lowlayer_status"
;;
esac
exit 0
fi
if [ "$changedX_ADB_RPFilter" = "1" ]; then
service_rp_filter_reconf "$obj"
fi
if [ "$changedX_ADB_ActiveLowerLayer" = "1" -a ${#newX_ADB_ActiveLowerLayer} -ne 0 ]; then
case "$lowlayer_ifname" in
"br"*)
cmclient -v br_obj GETV "$newX_ADB_ActiveLowerLayer.LowerLayers"
if ! is_pure_bridge "${br_obj%%".Port"*}"; then
cmclient SETE "$obj.X_ADB_Upstream" "false"
else
cmclient SETE "$obj.X_ADB_Upstream" "true"
fi
;;
*)
if is_lan_intf "${obj}"; then
cmclient SETE "$obj.X_ADB_Upstream" "false"
else
cmclient SETE "$obj.X_ADB_Upstream" "true"
fi
;;
esac
fi
case "$newX_ADB_ActiveLowerLayer" in
"Device.X_ADB_VPN"* )
return 0
;;
"Device.PPP.Interface"*)
is_ppp="true"
;;
esac
[ "$setX_ADB_DefaultRoute" = "1" ] && service_disable_def_route "$obj" "$newRouter" "$newX_ADB_DefaultRoute"
if [ -f /etc/ah/IPv6_helper_swisscom.sh -a "$setX_ADB_DefaultRoute" = "1" -a "$newX_ADB_DefaultRoute" = "true" ] && \
[  "$newEnable" = "true" -a "$newX_ADB_Upstream" != "false" ]; then
. /etc/ah/IPv6_helper_swisscom.sh
help_ipv6n_update_dflt_route
fi
[ "$setX_ADB_DHCPOpt121Enable" = "1" ] && service_conf_dhcp_route "$obj" "$newX_ADB_DHCPOpt121Enable"
help_active_lowlayer lowlayer "$obj"
if [ "$changedStatus" = "1" ]; then
if [ "$newStatus" = "Up" ]; then
if [ -z "$is_ppp" ]; then
if [ "$newX_ADB_AutoMTU" = "false" ]; then
help_lowlayer_set_mtu "$lowlayer" $newMaxMTUSize
maxMTU="$newMaxMTUSize"
fi
help_if_link_change "$lowlayer_ifname" "$newStatus" "$AH_NAME" "$maxMTU"
fi
service_do_reconf "$obj" "$lowlayer_ifname" "true"
[ "$is_ppp" != "true" ] && ipv6_service_do_reconf "$obj" "$lowlayer_ifname" "true"
elif [ "$newStatus" != "Dormant" ]; then
service_do_reconf "$obj" "$lowlayer_ifname" "false"
[ "$is_ppp" != "true" ] && ipv6_service_do_reconf "$obj" "$lowlayer_ifname" "false"
fi
return 0
fi
help_set_mtu "$lowlayer" "$lowlayer"
[ $changedEnable -eq 1 -o \( "$newEnable" = "true" -a "$user" = "init" \) ] && \
service_reconf "$obj" "$newStatus" "$newEnable" "$lowlayer_ifname" "$lowlayer" "$is_ppp"
if [ "$setReset" = 1 -a "$newReset" = "true" -a "$newLoopback" = "false" ]; then
case "$lowlayer" in
"Device.PPP.Interface"*)
cmclient -u "$AH_NAME" SET "$lowlayer.Reset" true
;;
"")
;;
*)	[ "$newStatus" = "Up" ] && \
cmclient -u "$AH_NAME" SET "Device.DHCPv4.Client.[Interface=$obj].Enable" true
;;
esac
fi
if [ "$newX_ADB_ProxyArp" = "true" ]; then
echo 1 > /proc/sys/net/ipv4/conf/${lowlayer_ifname}/proxy_arp
else
echo 0 > /proc/sys/net/ipv4/conf/${lowlayer_ifname}/proxy_arp
fi
;;
*"IPv6CP")
if [ "$changedLocalInterfaceIdentifier" = 1 ]; then
local ppp_ifname ppp_obj ip_obj
ppp_obj="${obj%.IPv6CP}"
cmclient -v ip_obj GETO "Device.IP.Interface.[LowerLayers=$ppp_obj]"
cmclient -v ppp_ifname GETV "$ppp_obj.Name"
if [ ${#newLocalInterfaceIdentifier} -eq 0 ]; then
ipv6_service_do_reconf "$ip_obj" "$ppp_ifname" "false"
else
ipv6_service_do_reconf "$ip_obj" "$ppp_ifname" "true"
fi
fi
;;
"Device.PPP.Interface"*)
local intf status enable ifname ppp_status ppp_trigger ppp_enable active_lowlayer
help_lowlayer_ifname_get ifname $obj
cmclient -v ppp_status GETV $obj.Status
cmclient -v ppp_trigger GETV $obj.ConnectionTrigger
cmclient -v ppp_enable GETV $obj.Enable
cmclient -v intf GETV 'InterfaceStack.[LowerLayer='$obj'].[HigherLayer>Device.IP.Interface].HigherLayer'
for intf in $intf; do
cmclient -v enable GETV $intf.Enable
cmclient -v active_lowlayer GETV $intf.X_ADB_ActiveLowerLayer
[ ${#active_lowlayer} -eq 0 -o "$active_lowlayer" = "$obj" ] || continue
if [ "$newConnectionStatus" = "Connected" ]; then
cmclient SETE "$intf.X_ADB_ActiveLowerLayer" "$obj"
if [ -d /etc/cm/tr098/ ]; then
cmclient -v ref GETV $obj.X_ADB_TR098Reference
cmclient SETE $intf.X_ADB_TR098Reference "$ref"
fi
fi
service_status_reconf "$intf" "$enable" "$ifname" "$ppp_status" "true" "$ppp_trigger" "$newConnectionStatus" "$ppp_enable"
done
;;
esac
}
service_add() {
case "$obj" in
*)
routing_create_device_rule $obj
[ -f /etc/ah/BridgingBridge.sh ] && /etc/ah/BridgingBridge.sh refreshlanrouting
;;
esac
}
service_delete() {
local objs tmp sixrdIf
case "$obj" in
*)
help_lowlayer_ifname_get lowlayer_ifname "$newLowerLayers"
cmclient DEL "Device.DHCPv4.Client.*.[Interface=$obj]"
cmclient DEL "Device.Routing.Router.*.IPv4Forwarding.*.[Interface=$obj]"
cmclient DEL "Device.DHCPv4.Server.Pool.[Interface=$obj]"
cmclient DEL "Device.NAT.InterfaceSetting.[Interface=$obj]"
cmclient DEL "Device.DNS.**.[Interface=$obj]"
cmclient SET "Device.NeighborDiscovery.InterfaceSetting.*.[Interface=$obj].Status" "Error_Misconfigured"
cmclient -v tmp GETV $obj.ULAEnable
if [ "$tmp" = "true" ]; then
cmclient SET "$obj.ULAEnable" "false"
fi
cmclient DEL "Device.Routing.Router.*.IPv6Forwarding.*.[Interface=$obj]"
cmclient DEL "Device.DHCPv6.Server.Pool.[Interface=$obj]"
cmclient DEL "Device.RouterAdvertisement.InterfaceSetting.[Interface=$obj]"
cmclient -v sixrdIf GETO "Device.IPv6rd.**.[TunnelInterface=$obj]"
if [ ${#sixrdIf} -ne 0 ]; then
cmclient -v tunneledIf GETV "$sixrdIf.TunneledInterface"
cmclient SET "$tunneledIf.Type" "Normal"
cmclient DEL "$sixrdIf"
fi
sixrdIf=""
cmclient -v sixrdIf GETO "Device.IPv6rd.**.[TunneledInterface=$obj]"
if [ ${#sixrdIf} -ne 0 ]; then
cmclient -v tunnelIf GETV "$sixrdIf.TunnelInterface"
cmclient SET "$tunnelIf.Type" "Normal"
cmclient DEL "$sixrdIf"
fi
local dhcp_obj
cmclient -v dhcp_obj GETO Device.DHCPv6.Client.[Interface=$obj].[Enable=true]
if [ -n "$dhcp_obj" ]; then
cmclient SET "$dhcp_obj.Enable" "false"
cmclient DEL "Device.IP.Interface.[X_ADB_Upstream=false].IPv6Prefix.[Origin=Child].[ParentPrefix>$obj]"
fi
if [ -f /etc/ah/VoIPNetwork.sh  ]; then
/etc/ah/VoIPNetwork.sh d $obj
fi
[ -f /etc/ah/BridgingBridge.sh ] && /etc/ah/BridgingBridge.sh refreshlanrouting
cmclient -v _type GETV "$obj.X_ADB_ConnectionType"
cmclient -v _upstr GETV "$obj.X_ADB_Upstream"
update_igmproxy_upstreaminterface "$obj" "$_type" "deleted" "$_upstr"
[ -f /etc/ah/ServicesReconf.sh ] && /etc/ah/ServicesReconf.sh "ipifdel" "$obj" "$_upstr"
;;
esac
}
finish_blank_config() {
local ip all_ips br_obj firstllayer llayers
cmclient -v all_ips GETO Device.IP.Interface
for ip in $all_ips; do
cmclient -v llayers GETV "$ip.LowerLayers"
help_lowlayer_ifname_get lowlayer_ifname "$llayers"
case "$lowlayer_ifname" in
"br"*)
firstllayer=${llayers%%,*}
cmclient -v br_obj GETV "$firstllayer.LowerLayers"
if ! is_pure_bridge "${br_obj%%".Port"*}"; then
cmclient SETE "$ip.X_ADB_Upstream" "false"
else
cmclient SETE "$ip.X_ADB_Upstream" "true"
fi
;;
*)
if is_lan_intf "${ip}"; then
cmclient SETE "$ip.X_ADB_Upstream" "false"
else
cmclient SETE "$ip.X_ADB_Upstream" "true"
fi
;;
esac
done
}
if [ $# -eq 1 ] && [ "$1" = "finishblank" ]; then
finish_blank_config
exit 0
fi
case "$op" in
s)
service_config
;;
d)
service_delete
;;
a)
service_add
;;
g)
case "$obj" in
*"InternetGatewayDevice"* )
cmclient -v tr181obj GETV "${obj%.Stats*}.X_ADB_TR181Name"
help_lowlayer_ifname_get ifname "$tr181obj"
;;
*)
help_lowlayer_ifname_get ifname "${obj%.Stats}"
;;
esac
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
;;
esac
exit 0
