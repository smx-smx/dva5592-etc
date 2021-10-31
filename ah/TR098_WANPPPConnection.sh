#!/bin/sh
AH_NAME="WANPPPConnection"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "USER_SKIP_RELATED_IF" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_link_stack() {
local _tr98obj="$1"
local _tr181obj="$2"
tr98_search="${_tr98obj%%.$AH_NAME*}"
cmclient -v is_atm GETO "Device.ATM.Link.*.[$PARAM_TR098=$tr98_search.WANDSLLinkConfig]"
if [ -n "$is_atm" ]; then
eth_required=`help98_switch_link_type "$tr98_search"`
if [ "$eth_required" = "true" ]; then
cmclient -v dsl_link GETV "$is_atm.$PARAM_TR098"
eth_link=`help98_add_tr181obj "$dsl_link" "Device.Ethernet.Link"`
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
eth_link=`help98_add_tr181obj "$ptm_link" "Device.Ethernet.Link"`
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
ip_if=`help98_add_tr181obj "$_tr98obj" "Device.IP.Interface"`
cmclient -u "$AH_NAME" SET "$_tr98obj.X_ADB_TR181_IPName" "$ip_if" > /dev/null
help181_set_param "$ip_if"."LowerLayers" "$_tr181obj"
cmclient -v ppp_enable GETV "$_tr181obj.Enable"
cmclient SET "$ip_if"."Enable" "$ppp_enable"
cmclient -v nat_if ADD "Device.NAT.InterfaceSetting"
cmclient SET Device.NAT.InterfaceSetting.$nat_if.Interface "$ip_if"
}
dnsserver_add() {
set -f
IFS=","
set -- $1
unset IFS
set +f
for arg; do
cmclient -v dnsobj GETO Device.DNS.Client.Server.*.[DNSServer=$arg].[Interface=$ip_obj]
if [ ${#dnsobj} -eq 0 ]; then
cmclient -v i ADD Device.DNS.Client.Server
cmclient SET Device.DNS.Client.Server.$i.Interface $ip_obj > /dev/null
cmclient SET Device.DNS.Client.Server.$i.Alias Server$i > /dev/null
cmclient SET Device.DNS.Client.Server.$i.DNSServer $arg > /dev/null
cmclient SET Device.DNS.Client.Server.$i.Enable true > /dev/null
cmclient -v i ADD Device.DNS.Relay.Forwarding
cmclient SET Device.DNS.Relay.Forwarding.$i.Interface $ip_obj > /dev/null
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
"DefaultGateway" )
cmclient -v l3obj GETO "InternetGatewayDevice.Layer3Forwarding.Forwarding.[Interface=$obj98].[DestIPAddress=]"
if [ ${#l3obj} -eq 0 ]; then
l3inst=`help98_add_object "InternetGatewayDevice.Layer3Forwarding.Forwarding"`
l3obj="InternetGatewayDevice.Layer3Forwarding.Forwarding.$l3inst"
help98_set_param "$l3obj.Interface" "$obj98"
fi
help98_set_param "$l3obj.GatewayIPAddress" "$val98"
;;
"DNSServers")
for trgt in $(cmclient GETV Device.DNS.Client.Server.*.[Interface=$ip_obj].[Type=Static].DNSServer)
do
case $val98 in
*"$trgt"* )
;;
* )
cmclient DEL Device.DNS.Client.Server.*.[Interface=$ip_obj].[Type=Static].[DNSServer=$trgt] > /dev/null
cmclient DEL Device.DNS.Relay.Forwarding.*.[Interface=$ip_obj].[Type=Static].[DNSServer=$trgt] > /dev/null
;;
esac
done
dnsserver_add "$val98"
;;
*)
;;
esac
}
service_get() {
local obj98="$1"
local param98="$2"
local ppp_status=""
local ipv4=""
local t1=""
local t2=""
paramval=""
ifname=`cmclient GETV "$ppp_obj.Name"`
case $param98 in
"DNSServers" )
for trgt in $(cmclient GETO Device.DNS.Client.Server.*.[Interface=$ip_obj])
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
"CurrentMRUSize" )
if [ -n "$ifname" ]; then
paramval=`cat /sys/class/net/$ifname/mtu 2>/dev/null`
fi
;;
"Uptime" )
paramval="0"
cmclient -v ppp_status GETV "$ppp_obj.ConnectionStatus"
if [ "$ppp_status" = "Connected" ]; then
for ipv4Obj in $(cmclient GETO "$ip_obj".IPv4Address); do
break;
done
cmclient -v ipv4 GETV "$ipv4Obj.Enable"
if [ "$ipv4" = "true" ]; then
read t2 < /proc/uptime
t2=${t2%%.*}
cmclient -v t1 GETV "$ipv4Obj.X_ADB_StartTime"
if [ "$t1" != "0" ] && [ "$t1" != "" ]; then
paramval="$(($t2-$t1))"
fi
fi
fi
;;
"LastConnectionError" )
if [ -e /tmp/ppp/$ppp_obj-lastconnerr ]; then
paramval=`cat /tmp/ppp/$ppp_obj-lastconnerr`
else
paramval="ERROR_NONE"
fi
;;
"RemoteIPAddress" )
is_l2tp=`help_strstr "$ppp_obj" "X_ADB_VPN"`
if [ -n "$is_l2tp" ]; then
cmclient -v paramval GETV "$ppp_obj.RemoteIPAddress"
else
cmclient -v paramval GETV "$ppp_obj.IPCP.RemoteIPAddress"
fi
;;
"TransportType" )
is_l2tp=`help_strstr "$ppp_obj" "X_ADB_VPN"`
cmclient -v lowlay GETV "$ppp_obj.LowerLayers"
is_atm=`help_strstr "$lowlay" "ATM"`
if [ -n "$is_l2tp" ]; then
paramval="L2TP"
elif [ -n "$is_atm" ]; then
paramval="PPPoA"
else
paramval="PPPoE"
fi
;;
"DefaultGateway")
cmclient -v paramval GETV Device.Routing.Router.*.IPv4Forwarding.[Interface="$ppp_obj"].[DestIPAddress=].GatewayIPAddress
;;
*)
;;
esac
echo "$paramval"
}
service_config() {
for i in DefaultGateway DNSServers
do
if eval [ \${set${i}:=0} -eq 1 ]; then
eval service_set_param "$obj" "$i" \"\$new${i}\"
fi
done
}
service_add() {
tr181obj=`help98_add_tr181obj "$obj" "Device.PPP.Interface"`
cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
service_link_stack "$obj" "$tr181obj"
}
service_delete() {
for layer3_obj in $(cmclient GETO "InternetGatewayDevice.Layer3Forwarding.Forwarding.[Interface=$obj]")
do
help98_del_object "$layer3_obj"
done
cmclient -v eth_link GETO "Device.Ethernet.Link.*.[$PARAM_TR098=$obj]"
if [ -n "$eth_link" ]; then
help181_del_object "$eth_link"
fi
for dns_obj in $(cmclient GETO "Device.DNS.Client.Server.*.[Interface=$ip_obj]")
do
help181_del_object "$dns_obj"
done
for relay_obj in $(cmclient GETO "Device.DNS.Relay.Forwarding.*.[Interface=$ip_obj]")
do
help181_del_object "$relay_obj"
done
help181_del_object "$ppp_obj"
if [ -n "$ip_obj" ]; then
help181_del_object "$ip_obj"
fi
}
case "$op" in
a)
service_add
;;
d)
cmclient -v ppp_obj GETV "$obj.X_ADB_TR181Name"
cmclient -v ip_obj GETV "$obj.X_ADB_TR181_IPName"
[ -n "$ppp_obj" ] && cmclient -v tr098_obj GETV "$ppp_obj.X_ADB_TR098Reference"
[ -n "$tr098_obj" -a "$obj" = "$tr098_obj" ] && service_delete
;;
g)
cmclient -v ppp_obj GETV "$obj.X_ADB_TR181Name"
cmclient -v ip_obj GETV "$obj.X_ADB_TR181_IPName"
[ -n "$ppp_obj" -a -n "$ip_obj" ] && cmclient -v tr098_obj GETV "$ppp_obj.X_ADB_TR098Reference"
if [ -n "$tr098_obj" -a "$obj" = "$tr098_obj" ]; then
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
cmclient -v ip_obj GETV "$obj.X_ADB_TR181_IPName"
[ -n "$tr181obj" ] && cmclient -v tr098_obj GETV "$tr181obj.X_ADB_TR098Reference"
[ -n "$tr098_obj" -a "$obj" = "$tr098_obj" ] && service_config
;;
esac
exit 0
