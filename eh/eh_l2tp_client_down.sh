#!/bin/sh
#udp:ip-down,ppp,*
#sync:max=1
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ipcalc.sh
EH_NAME="L2TP Client Down Event"
ip_obj=""
path=""
restore_default_route() {
local _i ipobj
local _router="$1"
cmclient -v _i GETO "Device.IP.Interface.*.[X_ADB_DefaultRoute=true].[Enable=true].[Status=Up]"
cmclient -v ipobj GETO "$_router.IPv4Forwarding.*.[Interface=$_i].[DestIPAddress=].[Enable=false]"
for def_route in $ipobj
do
cmclient SET "$def_route.Enable" "true"
break
done
}
update_routing_object() {
local _ipif="$1"
local _router="$2"
local _ip="$3"
cmclient -v i GETO "$_router.IPv4Forwarding.*.[Interface=$ip_obj].[StaticRoute=false].[DestIPAddress=$_ip]"
if [ -n "$i" ]; then
cmclient DEL "$i"
fi
}
update_ip_obj_st() {
cmclient -v ip_obj GETO "Device.IP.Interface.[LowerLayers,$path]"
if [ -n "$ip_obj" ]; then
echo "### $EH_NAME: SET <$ip_obj.Status> <LowerLayerDown> ###" > /dev/console
cmclient SET "$ip_obj.Status" "LowerLayerDown"
fi
}
update_ip_obj() {
if [ -n "$ip_obj" ]; then
cmclient -v ipv4_obj GETO "$ip_obj.IPv4Address.*.[AddressingType=IPCP]"
if [ -n "$ipv4_obj" ]; then
cmclient DEL "$ipv4_obj"
fi
fi
}
update_l2tp_client_object() {
local reset_val
local setm
local status_val
setm="$path.LocalIPAddress=	$path.RemoteIPAddress=	$path.DNSServers="
cmclient -v status_val GETV "$path.Status"
if [ "$status_val" != "Disconnected" ]; then
echo "### $EH_NAME: SETM <$path.Status> <Disconnected> ###" > /dev/console
setm="$setm	$path.Status=Disconnected"
fi
cmclient -v reset_val GETV "$path.Reset"
if [ "$reset_val" = "true" ]; then
echo "### $EH_NAME: SETM <$path.Reset> <false> ###" > /dev/console
setm="$setm	$path.Reset=false"
fi
cmclient SETM "$setm"
}
eventHandler_l2tpclient_down() {
cmclient -v path GETO "Device.X_ADB_VPN.Client.L2TP.*.[Alias=$LINKNAME]"
if [ "$path" = "" ]; then
exit 0
fi
update_ip_obj_st
cmclient -v is_default_ip GETV "$path.DefaultRoute"
if [ "$is_default_ip" = "false" ]; then
cmclient -v ip GETV "$path.RemoteIPAddress"
cmclient -v mask GETV "$path.SubnetMask"
help_calc_network network "$ip" "$mask"
update_routing_object "$ip_obj" "Device.Routing.Router.1" "$network"
else
update_routing_object "$ip_obj" "Device.Routing.Router.1"
restore_default_route "Device.Routing.Router.1"
fi
update_ip_obj
update_l2tp_client_object
cmclient SAVE
}
eventHandler_l2tpclient_down
