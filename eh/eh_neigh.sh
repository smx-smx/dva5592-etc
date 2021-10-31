#!/bin/sh
#neigh:*
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ipcalc.sh
. /etc/ah/helper_serialize.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_host.sh
. /etc/ah/IPv6_helper_functions.sh
EH_NAME="eh_neigh.sh"
ADD_OR_ADDS="ADD"
host_connected()
{
local neighbour="$1" ip_name="$2" ip_addr="$3" ifname="$4" mac="$neighbour" \
query="Device.Hosts.Host.*.[IPAddress=$ip_addr].[Active=true]" entry
[ "$neighbour" != "00:00:00:00:00:00" ] && query="$query.[PhysAddress=$neighbour]"
cmclient -v entry GETO "$query"
for entry in $entry; do
[ "$neighbour" = "00:00:00:00:00:00" ] && cmclient -v mac GETV $entry.PhysAddress
if ! arping -q -I $ip_name -w 1 -c 2 $ip_addr; then
help_host_disconnect "$entry" "$ip_name" "$mac"
fi
done
}
group="$OP"
event="$TYPE"
state="$OBJ"
ip_name="$IPNAME"
ip_addr="$ADDR"
neighbour="$MAC"
ifname="$IFNAME"
lookup_stat="$LOOKUP_STAT"
if [ $((0x${neighbour%%:*} & 3)) -eq 3 ]; then
exit 0
fi
case "$ip_addr" in
*:*)
ip_addr=`ipv6_short_format "$ip_addr"`
;;
esac
cmclient -v _globalIPv6Enable GETV  "Device.IP.IPv6Enable"
cmclient -v _enable GETV "Device.NeighborDiscovery.Enable"
if [ "$_globalIPv6Enable" = "true" -a  "$_enable" = "true" ]; then
cmclient -v itf_list GETO "Device.NeighborDiscovery.InterfaceSetting."
for entry in $itf_list; do
cmclient -v itf GETV "$entry.Interface"
[ -z "$itf" ] && continue
help_lowlayer_ifname_get itf $itf
if [ "$itf" = "$IFNAME" ]; then
cmclient -v itf GETV "$entry.Enable"
cmclient SET "$entry.Enable" "$itf"
fi
done
fi
if [ -f /etc/ah/helper_ovs.sh ]; then
case "$ifname" in
br*)
. /etc/ah/helper_ovs.sh
help_ovs_mac_lookup ifname "$neighbour" "$ifname"
;;
*) ;;
esac
fi
if [ "$group" = "RTMGRP_NEIGH" -a "$event" = "RTM_NEWNEIGH" ]; then
[ -z "$ip_name" ] && exit 0
case "$ip_addr" in
*:*) inet="inet6" ;;
*) inet="inet";;
esac
arp_entry=`ip -f "$inet" neigh show dev "$ip_name" | grep "^$ip_addr lladdr $neighbour "` || exit 0
case "$arp_entry" in
*"STALE"*)
cmclient -v known_host GETO "Device.Hosts.Host.*.[PhysAddress=$neighbour]"
if [ -n "$known_host" ]; then
cmclient -v known_host_ip GETV "$known_host.IPAddress"
if [ "$known_host_ip" = "$ip_addr" ]; then
cmclient SETE "${known_host}.[Active=false].Active true"
exit 0
fi
fi
;;
esac
[ -z "$ifname" ] && exit 0
[ "$lookup_stat" = "NOK" ] && help_mac_lookup ifname "$neighbour"
help_obj_from_ifname_get_var l1obj "$ifname"
if [ -n "$l1obj" ]; then
if is_wan_intf "$l1obj"; then
exit 0
fi
help_serialize "$neighbour" notrap
align_ip=0
local __pppConditional
local pppConditional
local ssid_reference
cmclient -v pppConditional GETO "Device.PPP.Interface.[Status=Up].[ConnectionStatus!Connected].[ConnectionTrigger=X_ADB_OnClient]"
for __pppConditional in ${pppConditional}; do
cmclient SET "${__pppConditional}.X_ADB_Reconnect" "true"
done
cmclient -v known_host GETO "Device.Hosts.Host.*.[PhysAddress=$neighbour]"
if [ -z "$known_host" ]; then
local entry
cmclient -v entry ADDIN Device.Hosts.Host
entry="Device.Hosts.Host.$entry"
setm_params="$entry.Layer1Interface=$l1obj"
cmclient -v ssid_reference GETO "Device.WiFi.SSID.*.[Name=$ifname]"
cmclient -v assocDevObj GETO "Device.WiFi.AccessPoint.*.[SSIDReference=$ssid_reference].AssociatedDevice.*.[MACAddress=$neighbour]"
if [ -n "$assocDevObj" ]; then
setm_params="$setm_params	$entry.AssociatedDevice=$assocDevObj"
fi
setm_params="$setm_params	$entry.PhysAddress=$neighbour"
cmclient -v is_dhcp GETO "Device.DHCPv4.Server.Pool.*.Client.[Chaddr=$neighbour].IPv4Address.[IPAddress=$ip_addr]"
if [ -n "$is_dhcp" ]; then
is_dhcp=${is_dhcp%.IPv4Address*}
setm_params="$setm_params	$entry.AddressSource=DHCP"
setm_params="$setm_params	$entry.DHCPClient=${is_dhcp}"
cmclient -v opt_12_v GETV "$is_dhcp.Option.[Tag=12].Value"
setm_params="$setm_params	$entry.HostName=$opt_12_v"
else
setm_params="$setm_params	$entry.AddressSource=Static"
fi
case "$ip_addr" in
*:*)
cmclient -v ipv6_index $ADD_OR_ADDS "$entry.IPv6Address"
setm_params="$setm_params	$entry.IPv6Address.$ipv6_index.IPAddress=$ip_addr"
;;
*)
setm_params="$setm_params	$entry.IPAddress=$ip_addr"
cmclient -v ipv4_index $ADD_OR_ADDS "$entry.IPv4Address"
setm_params="$setm_params	$entry.IPv4Address.$ipv4_index.IPAddress=$ip_addr"
;;
esac
align_ip=1
else
entry="$known_host"
setm_params="$entry.Layer1Interface=$l1obj"
case "$ip_addr" in
*:*)
cmclient -v ipv6_obj GETO "$entry.IPv6Address.[IPAddress=$ip_addr]"
if [ -z "$ipv6_obj" ]; then
cmclient -v ipv6_index $ADD_OR_ADDS "$entry.IPv6Address"
setm_params="$setm_params	$entry.IPv6Address.$ipv6_index.IPAddress=$ip_addr"
align_ip=1
fi
;;
*)	cmclient -v host_ip GETV "$entry.IPAddress"
if [ "$host_ip" != "$ip_addr" ]; then
setm_params="$setm_params	$entry.AddressSource=Static"
setm_params="$setm_params	$entry.IPAddress=$ip_addr"
cmclient -v ipv4addr GETO "$entry.IPv4Address"
if [ -z "$ipv4addr" ]; then
cmclient -v ipv4addr $ADD_OR_ADDS "$entry.IPv4Address"
ipv4addr="$entry.IPv4Address.$ipv4addr"
else
ipv4addr=${ipv4addr%IPAddress*}
fi
setm_params="$setm_params	$ipv4addr.IPAddress=$ip_addr"
setm_params="$setm_params	$entry.DHCPClient="
align_ip=1
fi
;;
esac
fi
if [ -f /sbin/cbpc-dnsp ]; then
cmclient -v Cbpc_enable GETV "Device.X_ADB_ParentalControl.Enable"
if [ "$Cbpc_enable" = "true" ]; then
cmclient -v mode GETV Device.X_ADB_ParentalControl.Mode
cmclient -v DefPolicy GETV Device.X_ADB_ParentalControl.DefaultPolicy
cmclient -v RHentry GETO "Device.X_ADB_ParentalControl.RestrictedHosts.Host.*.[MACAddress=$neighbour]"
if [ ${#RHentry} -eq 0 ]; then
cmclient -v tod_enable GETV $DefPolicy.TimeOfDayEnable
cmclient -v tod_profile GETV $DefPolicy.TimeOfDayProfile
tod_profile_id=${tod_profile##*.}
cmclient -v RHentry ADDIN "Device.X_ADB_ParentalControl.RestrictedHosts.Host."
set_p="Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.MACAddress=$neighbour"
set_p="$set_p	Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.TypeOfRestriction=TIMEOFDAY"
set_p="$set_p	Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.Enable=$tod_enable"
set_p="$set_p	Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.Blocked=false"
cmclient SETM "$set_p"
cmclient SET -u "RestrictedHostEntry" Device.X_ADB_ParentalControl.RestrictedHosts.Host.$RHentry.Profile $tod_profile_id
fi
cmclient -v PDevice GETO "Device.X_ADB_ParentalControl.PolicyDeviceAssociation.*.[MacAddress=$neighbour]"
if [ ${#PDevice} -eq 0 ]; then
cmclient -v PDevice $ADD_OR_ADDS "Device.X_ADB_ParentalControl.PolicyDeviceAssociation"
set_p="Device.X_ADB_ParentalControl.PolicyDeviceAssociation.$PDevice.MacAddress=$neighbour"
set_p="$set_p	Device.X_ADB_ParentalControl.PolicyDeviceAssociation.$PDevice.PreAssignedPolicy=$DefPolicy"
if [ "$mode" = "Advanced" ]; then
set_p="$set_p	Device.X_ADB_ParentalControl.PolicyDeviceAssociation.$PDevice.AllowPolicyOverride=true"
else
set_p="$set_p	Device.X_ADB_ParentalControl.PolicyDeviceAssociation.$PDevice.AllowPolicyOverride=false"
fi
cmclient SETM "$set_p"
fi
fi
fi
if [ "$align_ip" -eq 1 ]; then
if [ "${iface#eth*.}" != "$iface" -a "${l1obj#Device.Ethernet.Interface}" != "$l1obj" ]; then
cmclient -v br GETO "Bridging.Bridge.[Standard=802.1Q-2005].Port.[PVID=${iface##*.}].[LowerLayers=$l1obj]"
[ -n "$br" ] && help_ip_interface_get_first l3if "${br%.*}.1"
else
help_ip_interface_get_first l3if "$l1obj"
fi
[ -n "$l3if" ] && setm_params="$setm_params	$entry.Layer3Interface=$l3if"
fi
cmclient -v active GETV $entry.Active
[ "$active" = "false" ] && setm_params="$setm_params	$entry.Active=true"
setm_params="$setm_params	$entry.X_ADB_LastUp=`date -u +%s`"
cmclient SETM "$setm_params"
if [ "$_globalIPv6Enable" = "true" ]; then
local objects
cmclient -v objects GETO "Device.Hosts.Host.IPv6Address.[IPAddress=$ip_addr]"
for entry_host in $objects
do
if [ -n "${entry_host##*$entry*}" ] ;then
logger -t "IPv6LAN" -p 4 "ARS 1 - Duplicate address detected [$ip_addr/$neighbour]"
fi
done
fi
help_serialize_unlock "$neighbour"
[ -z "$known_host" ] && cmclient SAVE
fi
elif [ "$group" = "RTMGRP_NEIGH" -a "$event" = "RTM_DELNEIGH" ]; then
host_connected "$neighbour" "$ip_name" "$ip_addr" "$ifname"
fi
exit 0
