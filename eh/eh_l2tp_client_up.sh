#!/bin/sh
#udp:ip-up,ppp,*
#sync:max=1
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ipcalc.sh
EH_NAME="L2TP Client UP Event"
ip_obj=""
path=""
update_route_non_default() {
local _router="$1" _subnet="$2" _destip
help_calc_network _destip "$IPREMOTE" "$_subnet"
cmclient -v i GETO "$_router.IPv4Forwarding.[Interface=$ip_obj].[StaticRoute=false].[DestIPAddress=$_destip]"
if [ -z "$i" ]; then
cmclient -v i_idx ADD "$_router.IPv4Forwarding"
i="$_router.IPv4Forwarding.$i_idx"
fi
cmclient SET "$i".Enable false
cmclient SET "$i".Interface "$ip_obj"
cmclient SET "$i".StaticRoute false
cmclient SET "$i".DestIPAddress "$destip"
cmclient SET "$i".DestSubnetMask "$_subnet"
cmclient SET "$i".Enable true
}
update_routing_object() {
local _router="$1"
cmclient -v i GETO "$_router.IPv4Forwarding.[Interface=$ip_obj].[StaticRoute=false].[DestIPAddress=]"
if [ -z "$i" ]; then
i_idx=`cmclient ADD "$_router.IPv4Forwarding"`
i="$_router.IPv4Forwarding.$i_idx"
fi
cmclient SET "$i".Enable false
cmclient SET "$i".Interface "$ip_obj"
cmclient SET "$i".StaticRoute false
cmclient SET "$i".GatewayIPAddress "$IPREMOTE"
cmclient SET "$i".Enable true
cmclient -v ip_if_obj_low GETV "$path.Interface"
cmclient SET "$_router.IPv4Forwarding.[Interface=$ip_if_obj_low].[StaticRoute=false].[DestIPAddress=].Enable" false
}
update_ip_obj() {
local ip_obj_index ipv4_index ipv4_obj
cmclient -v ip_obj GETO "Device.IP.Interface.[LowerLayers,$path]"
if [ -z "$ip_obj" ]; then
cmclient -v ip_obj_index ADD "Device.IP.Interface"
ip_obj="Device.IP.Interface."$ip_obj_index
echo "### $EH_NAME: SET <$ip_obj.LowerLayers> <$path> ###" > /dev/console
cmclient SET "$ip_obj.LowerLayers" "$path"
fi
echo "### $EH_NAME: SET <$ip_obj.Status> <Up> ###" > /dev/console
cmclient SET "$ip_obj.Status" "Up"
echo "### $EH_NAME: SET <$ip_obj.Enable> <true> ###" > /dev/console
cmclient SET "$ip_obj.Enable" "true"
cmclient -v ipv4_obj GETO "$ip_obj.IPv4Address.*.[AddressingType=IPCP]"
if [ -z "$ipv4_obj" ]; then
cmclient -v ipv4_index ADD $ip_obj.IPv4Address
if [ "$ipv4_index" = "ERROR" ]; then
echo "$EH_NAME: ERROR adding obj <$ip_obj.IPv4Address>" > /dev/console
exit 0
fi
ipv4_obj=$ip_obj"."IPv4Address"."$ipv4_index
fi
echo "### $EH_NAME: SET <$ipv4_obj.IPAddress> <$IPLOCAL> ###" > /dev/console
cmclient SET "$ipv4_obj.IPAddress" "$IPLOCAL"
subnet_mask=`ifconfig "$IFNAME" | grep "inet addr" | awk -F: '{print $4}' | awk '{print $1}'`
echo "### $EH_NAME: SET <$ipv4_obj.SubnetMask> <$subnet_mask> ###" > /dev/console
cmclient SET "$ipv4_obj.SubnetMask" "$subnet_mask"
echo "### $EH_NAME: SET <$ipv4_obj.AddressingType> <IPCP> ###" > /dev/console
cmclient SET "$ipv4_obj.AddressingType" "IPCP"
echo "### $EH_NAME: SET <$ipv4_obj.Enable> <true> ###" > /dev/console
cmclient SET "$ipv4_obj.Enable" "true"
}
update_l2tp_client_object() {
local DNSServers
if [ "$DNS1" = "$DNS2" ]; then
DNSServers="$DNS1"
else
DNSServers="$DNS1,$DNS2"
fi
echo "### $EH_NAME: SET <$path.LocalIPAddress> <$IPLOCAL> ###" > /dev/console
echo "### $EH_NAME: SET <$path.RemoteIPAddress> <$IPREMOTE> ###" > /dev/console
echo "### $EH_NAME: SET <$path.DNSServers> <$DNSServers> ###" > /dev/console
echo "### $EH_NAME: SET <$path.Status> <Connected> ###" > /dev/console
setm="${path}.LocalIPAddress=${IPLOCAL}"
setm="${setm}	${path}.RemoteIPAddress=${IPREMOTE}"
setm="${setm}	${path}.DNSServers=${DNSServers}"
setm="${setm}	${path}.Status=Connected"
cmclient -v reset_val GETV "$path.Reset"
if [ "$reset_val" = "true" ]; then
echo "### $EH_NAME: SETM <$path.Reset> <false> ###" > /dev/console
setm="${setm}	${path}.Reset=false"
fi
cmclient SETM "$setm"
}
eventHandler_l2tpclient_up() {
cmclient -v path GETO "Device.X_ADB_VPN.Client.L2TP.*.[Alias=$LINKNAME]"
if [ "$path" = "" ]; then
exit 0
fi
update_l2tp_client_object
update_ip_obj
cmclient -v is_default_route GETV "$path.DefaultRoute"
if [ "$is_default_route" = "true" ]; then
update_routing_object "Device.Routing.Router.1"
else
cmclient -v subnet GETV "$path.SubnetMask"
if [ -n "$subnet" ]; then
update_route_non_default "Device.Routing.Router.1" "$subnet"
fi
fi
cmclient SAVE
}
eventHandler_l2tpclient_up
