#!/bin/sh
AH_NAME="WANIPConnection"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_tr098.sh
service_link_stack() {
local _tr98obj="$1"
local _tr181obj="$2"
tr98_search="${_tr98obj%%.$AH_NAME*}"
help98_link_tr181obj "$tr98_search.WANPPPConnection" "$_tr181obj" "Device.PPP.Interface"
is_ppp=$?
[ "$is_ppp" -eq 1 ] && return
cmclient -v is_atm GETO "Device.ATM.Link.*.[$PARAM_TR098=$tr98_search.WANDSLLinkConfig]"
if [ -n "$is_atm" ]; then
eth_required=$(help98_switch_link_type "$tr98_search")
if [ "$eth_required" = "true" ]; then
cmclient -v dsl_link GETV "$is_atm.$PARAM_TR098"
eth_link=$(help98_add_tr181obj "$dsl_link" "Device.Ethernet.Link")
help181_set_param "$eth_link"."LowerLayers" "$is_atm"
cmclient SET "$eth_link"."Enable" "true"
help181_set_param "$_tr181obj.LowerLayers" "$eth_link"
else
help181_set_param "$_tr181obj.LowerLayers" "$is_atm"
fi
else
cmclient -v is_ptm GETO "Device.PTM.Link.*.[$PARAM_TR098=$tr98_search.WANPTMLinkConfig]"
if [ -n "$is_ptm" ]; then
cmclient -v ptm_link GETV "$is_ptm.$PARAM_TR098"
eth_link=$(help98_add_tr181obj "$ptm_link" "Device.Ethernet.Link")
help181_set_param "$eth_link"."LowerLayers" "$is_ptm"
cmclient SET "$eth_link"."Enable" "true"
help181_set_param "$_tr181obj.LowerLayers" "$eth_link"
else
cmclient -v is_waneth GETO "Device.Ethernet.Link.*.[$PARAM_TR098=$tr98_search.WANEthernetLinkConfig]"
if [ ${#is_waneth} -gt 0 ]; then
cmclient -v vlan_obj GETO "Device.Ethernet.VLANTermination.*.[$PARAM_TR098=$tr98_search.WANEthernetLinkConfig]"
[ ${#vlan_obj} -gt 0 ] && help181_set_param "$_tr181obj.LowerLayers" "$vlan_obj" || help181_set_param "$_tr181obj.LowerLayers" "$is_waneth"
fi
fi
fi
}
dnsserver_add() {
local tmp=""
set -f
IFS=","
set -- $1
unset IFS
set +f
for arg; do
cmclient -v tmp GETO Device.DNS.Client.Server.*.[DNSServer=$arg].[Interface=$tr181obj]
if [ -z "$tmp" ]; then
cmclient -v i ADD Device.DNS.Client.Server
cmclient SET Device.DNS.Client.Server.$i.Interface $tr181obj > /dev/null
cmclient SET Device.DNS.Client.Server.$i.Alias Server$i > /dev/null
cmclient SET Device.DNS.Client.Server.$i.DNSServer $arg > /dev/null
cmclient SET Device.DNS.Client.Server.$i.Enable true > /dev/null
cmclient -v i ADD Device.DNS.Relay.Forwarding
cmclient SET Device.DNS.Relay.Forwarding.$i.Interface $tr181obj > /dev/null
cmclient SET Device.DNS.Relay.Forwarding.$i.Alias Forwarding$i > /dev/null
cmclient SET Device.DNS.Relay.Forwarding.$i.DNSServer $arg > /dev/null
cmclient SET Device.DNS.Relay.Forwarding.$i.Type Static > /dev/null
cmclient SET Device.DNS.Relay.Forwarding.$i.Enable true > /dev/null
fi
done
}
service_set_param() {
local obj98="$1"
local param98="$2"
local val98="$3"
case "$param98" in
"AddressingType")
cmclient -v dhcp_obj GETO "Device.DHCPv4.Client.[Interface=$tr181obj].[X_ADB_TR098Reference=$obj98]"
if [ "$val98" = "DHCP" ]; then
if [ -z "$dhcp_obj" ]; then
dhcp_obj=$(help98_add_tr181obj "$obj98" "Device.DHCPv4.Client")
help181_set_param "$dhcp_obj.Interface" "$tr181obj"
fi
cmclient -v ipv4_enable GETV "$tr181obj.Enable"
help181_set_param "$dhcp_obj.Enable" "$ipv4_enable"
for ipv4_obj in `cmclient GETO "$tr181obj.IPv4Address.[AddressingType=Static]"`
do
help181_del_object "$ipv4_obj"
done
else
cmclient -v ipv4static_obj GETO "$tr181obj.IPv4Address.[AddressingType=Static].[X_ADB_TR098Reference=$obj98]"
if [ -z "$ipv4static_obj" ]; then
ipv4static_obj=$(help98_add_tr181obj "$obj98" "$tr181obj.IPv4Address")
help181_set_param "$ipv4static_obj.AddressingType" "$val98"
fi
if [ -n "$dhcp_obj" ]; then
help181_del_object "$dhcp_obj"
fi
for ipv4_obj in `cmclient GETO "$tr181obj.IPv4Address.[AddressingType=DHCP]"`
do
help181_del_object "$ipv4_obj"
done
fi
;;
"DefaultGateway" )
cmclient -v l3obj GETO "InternetGatewayDevice.Layer3Forwarding.Forwarding.[Interface=$obj98].[DestIPAddress=]"
if [ -z "$l3obj" ]; then
l3inst=$(help98_add_object "InternetGatewayDevice.Layer3Forwarding.Forwarding")
l3obj="InternetGatewayDevice.Layer3Forwarding.Forwarding.$l3inst"
help98_set_param "$l3obj.Interface" "$obj98"
fi
help98_set_param "$l3obj.GatewayIPAddress" "$val98"
;;
"DNSServers")
for trgt in `cmclient GETV Device.DNS.Client.Server.*.[Interface=$tr181obj].[Type=Static].DNSServer`
do
case $val98 in
*"$trgt"* )
;;
* )
cmclient DEL Device.DNS.Client.Server.*.[Interface=$tr181obj].[Type=Static].[DNSServer=$trgt] > /dev/null
cmclient DEL Device.DNS.Relay.Forwarding.*.[Interface=$tr181obj].[Type=Static].[DNSServer=$trgt] > /dev/null
;;
esac
done
dnsserver_add $val98
;;
*)
;;
esac
}
service_get() {
local obj98="$1" param98="$2" tmp=""
case $param98 in
"ConnectionStatus")
cmclient -v _tr181val GETV "$tr181obj.Status"
paramval=$(help98_get_connstatus "$_tr181val")
;;
"DNSServers" )
for trgt in `cmclient GETO Device.DNS.Client.Server.*.[Interface=$tr181obj]`
do
cmclient -v dnstarget GETV $trgt.DNSServer
if [ -n "$dnstarget" ]; then
if [ -z "$dnslist" ]; then
dnslist="$dnstarget"
else
dnslist="$dnslist"",""$dnstarget"
fi
fi
done
paramval="$dnslist"
;;
"MaxMTUSize" )
help_lowlayer_ifname_get ifname "$tr181obj"
if [ -n "$ifname" ]; then
if [ -d /sys/class/net/"$ifname" ]; then
mtu=$(cat /sys/class/net/"$ifname"/mtu)
fi
fi
paramval="$mtu"
;;
"ConnectionType" )
cmclient -v refObj GETV "$obj".X_ADB_TR181Name
cmclient -v LowerLay GETV "$refObj".LowerLayers
case "${LowerLay}" in
*"ATM.Link"*)
cmclient -v LinkType GETV "${LowerLay}".LinkType
if [ -n "$LinkType" ]; then
case "${LinkType}" in
EoA)
paramval="IP_Bridged"
;;
*)
paramval="IP_Routed"
;;
esac
else
paramval="Unconfigured"
fi
;;
*"Ethernet.VLANTermination"*)
paramval="IP_Routed"
;;
*)
paramval="IP_Routed"
;;
esac
;;
"Uptime" )
paramval="0"
cmclient -v ip_enable GETV "$tr181obj.Enable"
if [ "$ip_enable" = "true" ]; then
t2=$(cut -f 1 -d . /proc/uptime)
cmclient -v t1 GETV "$tr181obj.IPv4Address.1.X_ADB_StartTime"
if [ "$t1" != "0" ] && [ "$t1" != "" ]; then
paramval=$(($t2-$t1))
fi
fi
;;
*)
;;
esac
echo "$paramval"
}
service_config() {
for i in AddressingType DefaultGateway DNSServers
do
if eval [ \${set${i}:=0} -eq 1 ]; then
eval service_set_param "$obj" "$i" \"\$new${i}\"
fi
done
}
service_add() {
local nat_if
tr181obj=$(help98_add_tr181obj "$obj" "Device.IP.Interface")
cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
service_link_stack "$obj" "$tr181obj"
cmclient -v nat_if ADD "Device.NAT.InterfaceSetting"
cmclient SET Device.NAT.InterfaceSetting.$nat_if.Interface "$tr181obj"
}
service_delete() {
for layer3_obj in `cmclient GETO "InternetGatewayDevice.Layer3Forwarding.Forwarding.[Interface=$obj]"`
do
help98_del_object "$layer3_obj"
done
cmclient -v eth_link GETO "Device.Ethernet.Link.*.[$PARAM_TR098=$obj]"
[ -n "$eth_link" ] && help181_del_object "$eth_link"
cmclient -v dhcp_obj GETO "Device.DHCPv4.Client.*.[Interface=$tr181obj].[$PARAM_TR098=$obj]"
[ -n "$dhcp_obj" ] && help181_del_object "$dhcp_obj"
for dns_obj in `cmclient GETO "Device.DNS.Client.Server.*.[Interface=$tr181obj]"`
do
help181_del_object "$dns_obj"
done
for relay_obj in `cmclient GETO "Device.DNS.Relay.Forwarding.*.[Interface=$tr181obj]"`
do
help181_del_object "$relay_obj"
done
help181_del_object "$tr181obj"
}
case "$op" in
a)
service_add
;;
d)
cmclient -v tr181obj GETV "$obj.X_ADB_TR181Name"
[ -n "$tr181obj" ] && service_delete
;;
g)
cmclient -v tr181obj GETV "$obj.X_ADB_TR181Name"
if [ -n "$tr181obj" ]; then
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
else
for arg # Arg list as separate words
do
echo ""
done
fi
;;
s)
cmclient -v tr181obj GETV "$obj.X_ADB_TR181Name"
[ -n "$tr181obj" ] && service_config
;;
esac
exit 0
