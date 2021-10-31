#!/bin/sh
#udp:ip-up,ppp,*
#sync:max=1
. /etc/ah/helper_ipcalc.sh
EH_NAME="PPTP Client UP Event"
ip_obj=""
path=""
update_ip_obj() {
local to_enable=0 ip_obj_index ipv4_obj ipv4_index setm
cmclient -v ip_obj GETO "Device.IP.Interface.[LowerLayers,$path]"
if [ ${#ip_obj} -eq 0 ]; then
cmclient -v ip_obj_index ADD "Device.IP.Interface"
ip_obj="Device.IP.Interface."$ip_obj_index
cmclient SET "$ip_obj.LowerLayers" "$path"
to_enable=1
fi
cmclient -v ipv4_obj GETO "$ip_obj.IPv4Address.*.[AddressingType=IPCP]"
if [ -z "$ipv4_obj" ]; then
cmclient -v ipv4_index ADDS $ip_obj.IPv4Address
if [ "$ipv4_index" = "ERROR" ]; then
echo "$EH_NAME: ERROR adding obj <$ip_obj.IPv4Address>" > /dev/console
exit 0
fi
ipv4_obj=$ip_obj"."IPv4Address"."$ipv4_index
fi
subnet_mask=`ifconfig "$IFNAME" | grep "inet addr" | awk -F: '{print $4}' | awk '{print $1}'`
[ $to_enable -eq 1 ] && cmclient SET "$ip_obj.Enable" "true"
cmclient SET "$ip_obj.Status" "Up"
setm="$ipv4_obj.IPAddress=$IPLOCAL"
setm="$setm	$ipv4_obj.SubnetMask=$subnet_mask"
setm="$setm	$ipv4_obj.AddressingType=IPCP"
setm="$setm	$ipv4_obj.Enable=true"
cmclient SETM "$setm"
}
update_pptp_client_object() {
local setm reset_val
setm="${path}.LocalIPAddress=${IPLOCAL}"
setm="${setm}	${path}.RemoteIPAddress=${IPREMOTE}"
setm="${setm}	${path}.Status=Connected"
cmclient -v reset_val GETV "$path.Reset"
[ "$reset_val" = "true" ] && setm="${setm}	${path}.Reset=false"
cmclient SETM "$setm"
}
updateRoutingRouter() {
local ip_router tmp setm def_route ip_route is_default
cmclient -v ip_router GETV "$ip_obj.Router"
if [ -z "$ip_router" ]; then
cmclient -v router_index ADD "Device.Routing.Router"
ip_router="Device.Routing.Router.${router_index}"
cmclient SET "$ip_router.Enable" "true"
cmclient SET "$ip_obj.Router" "$ip_router"
fi
cmclient -v is_default GETV "$ip_obj.X_ADB_DefaultRoute"
cmclient -v def_route GETO "$ip_router.IPv4Forwarding.[Interface=$ip_obj].[DestIPAddress=]"
if [ -z "$def_route" ]; then
cmclient -v iproute_index ADD "$ip_router.IPv4Forwarding"
def_route="$ip_router.IPv4Forwarding.$iproute_index"
fi
for ip_route in $def_route; do
setm="$ip_route.GatewayIPAddress=$IPREMOTE"
setm="$setm	$ip_route.Interface=$ip_obj"
setm="$setm	$ip_route.Origin=IPCP"
cmclient -v tmp GETV $ip_route.X_ADB_AutoGateway
[ "$tmp" = "false" ] && setm="$setm	$ip_route.StaticRoute=false"
[ "$is_default" = "true" ] && setm="$setm	$ip_route.Enable=true"
cmclient SETM "$setm"
done
}
eventHandler_pptpclient_up() {
cmclient -v path GETO "Device.X_ADB_VPN.Client.PPTP.*.[Alias=$LINKNAME]"
[ ${#path} -eq 0 ] && exit 0
update_pptp_client_object
update_ip_obj
updateRoutingRouter
cmclient SAVE
}
eventHandler_pptpclient_up
