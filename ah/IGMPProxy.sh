#!/bin/sh
AH_NAME="IGMPProxy"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ -f /tmp/upgrading.lock ] && [ "$op" != "g" ] && exit 0
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_svc.sh
IGMPPROXY_CONF=/tmp/yamp.conf
IGMPPROXY_PID=/tmp/yamp.pid
start_igmpproxy()
{
local i=0 upif lower pid
[ ! -f $IGMPPROXY_PID ] && help_svc_start "yamp -c $IGMPPROXY_CONF -p $IGMPPROXY_PID" '' 'daemon' '' '' '15' "$IGMPPROXY_PID"
help_svc_wait_proc_started "" "$IGMPPROXY_PID" 100
if [ -f $IGMPPROXY_PID ]; then
IFS=","
set -- $newUpstreamInterfaces
unset IFS
for upif do
help_lowlayer_ifname_get "lower" "$upif"
echo $newWANVersion > /proc/sys/net/ipv4/conf/$lower/force_igmp_version
done
fi
}
stop_igmpproxy()
{
local pid
ebtables -t filter -D OUTPUT -j IGMPPROXY
ebtables -t filter -F IGMPPROXY
ebtables -t filter -X IGMPPROXY
[ -f $IGMPPROXY_PID ] && help_svc_stop yamp "$IGMPPROXY_PID" 15
rm -f $IGMPPROXY_PID
}
conf_changed()
{
help_is_changed Enable UpstreamInterfaces UpstreamInterfaceAutoConfig \
DownstreamInterfaces FastLeave LastMemberQueryCnt LastMemberQueryInt \
LANVersion WANVersion SkipGroups Snooping && return 0
[ "$do_refresh" = "true" -o "$setRefresh" = "1" ] && return 0
return 1
}
set_status()
{
local _status=$1
cmclient -u "${AH_NAME}${obj}" SET Device.Services.X_ADB_IGMPProxy.Status $_status
}
igmp_refresh()
{
local vars line
cmclient -v vars GET Services.X_ADB_IGMPProxy.
for line in $vars; do
IFS=";"
line=${line#Device.Services.X_ADB_IGMPProxy.}
set -- $line
unset IFS
eval "new$1=$2"
done
do_refresh="true"
oldDownstreamInterfaces=$newDownstreamInterfaces
igmpproxy_event
}
multicast_isolation_get_portlist()
{
local ports port lower name portlist isolation
[ -z "$1" ] && return
[ "$1" = "wan" ] && isolation="X_ADB_MulticastIsolation" || isolation="X_ADB_WAN_MulticastIsolation"
cmclient -v ports GETO Device.Bridging.Bridge.*.[$isolation=true].Port.*.[ManagementPort=false]
for port in $ports; do
is_$1_intf "$port" && continue
cmclient -v lower GETV "$port.LowerLayers"
help_lowlayer_ifname_get "name" "$lower"
portlist="$portlist $name"
done
eval "$2=\"$portlist\""
}
multicast_isolation_event()
{
[ "$changedX_ADB_MulticastIsolation" = "1" -o "$changedX_ADB_WAN_MulticastIsolation" = "1" ] && \
igmp_refresh
}
set_addr()
{
local ifindex
[ -f /sys/class/net/$name/ifindex ] || return
read ifindex < /sys/class/net/$name/ifindex
ip addr $cmd 0.0.0.$ifindex/32 dev $name
}
config_dummy_addr_single()
{
local intf=$1 cmd=$2 ipintf uls ul name
help_ip_interface_get_first ipintf "$intf"
[ -n "$ipintf" ] && return
if [ "${intf%%.[0-9]*}" = "Device.Bridging.Bridge" ]; then
cmclient -v name GETV ${intf%.[0-9]*}.[ManagementPort=true].Name
[ -n "$name" ] && set_addr $name
fi
cmclient -v uls GETO Device.**.[LowerLayers="$intf"]
for ul in $uls; do
if [ "${ul%%.[0-9]*}" = "Device.Bridging.Bridge" ]; then
cmclient -v name GETV "Device.Bridging.Bridge.**.[LowerLayers,$ul].[ManagementPort=true].Name"
set_addr $name
break
fi
done
}
config_dummy_addr()
{
local intfs=$1 cmd=$2 intf hl
IFS=","
set -- $intfs
unset IFS
for intf do
if [ "${intf%%.[0-9]*}" = "Device.Ethernet.Interface" ]; then
cmclient -v hl GETV "Device.InterfaceStack.[LowerLayer=$intf].HigherLayer"
for hl in $hl; do
config_dummy_addr_single "$hl" "$cmd"
done
else
config_dummy_addr_single "$intf" "$cmd"
fi
done
}
skipgroup_ip2int() {
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=.
set -- $1 $2
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
eval $1=0
[ $# -eq 5 ] && eval $1=$(printf '%x' $((($5 & 0xFF) << 24 | ($4 & 0xFF) << 16 | ($3 & 0xFF) << 8 | $2 & 0xFF)))
}
snoop_skip_group()
{
local skip_addr i=0
while pidof yamp && [ $i -le 100 ]; do
sleep 0.1
i=$((i + 1))
done
IFS=","
for skip_addr in $newSkipGroups; do
skipgroup_ip2int skip_addr $skip_addr
echo "add $skip_addr 0" > /proc/hwswitch/default/snoop_ctl
done
unset IFS
}
igmpproxy_event()
{
local skip_addr=""
. /etc/ah/helper_serialize.sh && help_serialize
config_dummy_addr $oldDownstreamInterfaces "del"
if [ "$changedEnable" = "1" -a "$newEnable" = "false" ]; then
help_iptables -t filter -F IGMPProxyIn
stop_igmpproxy
set_status Disabled
[ "$newSnooping" = "true" ] && snoop_skip_group
return
fi
if [ "$newEnable" = "true" ]; then
set_status Enabled
if [ -z "$newUpstreamInterfaces" ]; then
set_status NoUpstreamInterface
else
local status ipaddr ipaddrs isup=0 hasip=0
IFS=","
set -- $newUpstreamInterfaces
unset IFS
for upif do
cmclient -v status GETV "$upif.Status"
if [ "$status" = "Up" ]; then
isup=1
hasip=0
cmclient -v ipaddrs GETV "$upif.IPv4Address.[Enable=true].IPAddress"
for ipaddr in $ipaddrs; do
if [ -n "$ipaddr" ]; then
hasip=1
break
fi
done
[ $hasip -eq 1 ] && break
fi
done
if [ $isup -eq 0 ]; then
set_status UpstreamDown
elif [ $hasip -eq 0 ]; then
set_status WaitingUpstreamAddress
fi
fi
if [ ! -x /sbin/yamp ]; then
set_status Disabled
return
fi
config_dummy_addr $newDownstreamInterfaces "add"
! conf_changed && return # Nothing to do
ebtables -t filter -N IGMPPROXY -P RETURN
ebtables -t filter -D OUTPUT -j IGMPPROXY
ebtables -t filter -A OUTPUT -j IGMPPROXY
ebtables -t filter -F IGMPPROXY
help_iptables -t filter -F IGMPProxyIn
local name aif dif iflist intfs intf wififs downifs upif ovsifs ovsbr ovsport name_suffix
cmclient -v intfs GETO Device.**.[Upstream=false]
cmclient -v wififs GETO Device.WiFi.SSID
cmclient -v brifs GETO Device.Bridging.Bridge.*.Port.[Name!].[Name!fk].[ManagementPort!true].[X_ADB_FakePort!true]
for intf in $intfs $wififs $brifs; do
cmclient -v name GETV "$intf.Name"
if ! help_is_in_list "$aif" "$name"; then
if help_is_in_list "$newDownstreamInterfaces" "$intf"; then
cmclient -v ovsport GETO "Device.Bridging.Bridge.[X_ADB_BridgeType=OVS].Port.[ManagementPort!true].[LowerLayers=${intf}]"
[ ${#ovsport} -gt 0 ] && intf=$ovsport
cmclient -v ovsbr GETV "Device.Bridging.Bridge.[X_ADB_BridgeType=OVS].Port.[LowerLayers,${intf}].[ManagementPort=true].Name"
[ ${#ovsbr} -gt 0 ] && ovsifs="${ovsifs} ${ovsbr},${name}"
downifs="$downifs $name"
aif="${aif:+$aif,}$name"
elif ! help_is_in_list "$dif" "$name"; then
dif="${dif:+$dif,}$name"
fi
fi
done
cmclient -v brifs GETO Device.Bridging.Bridge.*.Port.[Name!].[Name!fk].[ManagementPort!true].[X_ADB_FakePort=true]
for intf in $brifs; do
cmclient -v name GETV "$intf.Name"
cmclient -v name_suffix GETV "${intf%%.Port.[0-9]*}.Port.[ManagementPort=true].Name"
[ -n "$name_suffix" ] && name=$name"_"$name_suffix
if ! help_is_in_list "$aif" "$name"; then
cmclient -v iflist GETV "$intf.LowerLayers"
if help_is_in_list "$newDownstreamInterfaces" "$iflist"; then
downifs="$downifs $name"
aif="${aif:+$aif,}$name"
fi
fi
done
IFS=","
for iflist in $dif
do
if ! help_is_in_list "$aif" "$iflist"; then
for skip_addr in $newSkipGroups; do
ebtables -t filter -A IGMPPROXY -p IPv4 -o $iflist --ip-dst "$skip_addr" -j RETURN
done
ebtables -t filter -A IGMPPROXY -p IPv4 -o $iflist --ip-dst 239.0.0.0/8 -j DROP
fi
done
for iflist in $aif
do
help_iptables -t filter -A IGMPProxyIn -m physdev -p igmp --physdev-in $iflist -j ACCEPT
done
set -- $newUpstreamInterfaces
unset IFS
for upif do
help_lowlayer_ifname_get "name" "$upif"
upifs="$upifs $name"
done
local quickleave=1 snoop=1 loglevel lan_portlist wan_portlist
[ "$newFastLeave" = "false" ] && quickleave=0
[ "$newSnooping" = "false" ] && snoop=0
echo $snoop > /proc/hwswitch/default/snooping
cmclient -v loglevel GETV Device.X_ADB_SystemLog.Service.[Alias=IGMP Proxy].Priority
multicast_isolation_get_portlist "wan" lan_portlist
[ "$quickleave" = "1" ] &&\
echo 1 > /proc/net/ip_mr_expire ||\
echo 10 > /proc/net/ip_mr_expire
cat > $IGMPPROXY_CONF <<-EOF
upstream$upifs
downstream$downifs
ovs$ovsifs
fastleave $quickleave
lmqc $newLastMemberQueryCnt
lmqi $newLastMemberQueryInt
lanversion $newLANVersion
wanversion $newWANVersion
snooping $snoop
loglevel $loglevel
skip $newSkipGroups
isolation$lan_portlist$wan_portlist
EOF
start_igmpproxy
else
[ "$newSnooping" = "true" ] && snoop_skip_group
fi
}
case "$obj" in
Device.Services.X_ADB_IGMPProxy)
igmpproxy_event
;;
Device.Bridging.Bridge.*)
multicast_isolation_event
;;
esac
exit 0
