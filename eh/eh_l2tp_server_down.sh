#!/bin/sh
#udp:ip-down,ppp,*
#sync:max=1
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tunnel.sh
EH_NAME="L2TP Down Event"
update_ip_obj() {
cmclient -v ip_obj GETO "Device.IP.Interface.*.[Name=$IFNAME]"
if [ "$ip_obj" = "" ]; then
echo "### IP Interface Object Not found ###" > /dev/console
exit 0
fi
cmclient DEL "$ip_obj"
}
update_l2tp_server_object() {
cmclient -v status_val GETV $object".Status"
cmclient -v enable_val GETV "$object.Enable"
if [ "$enable_val" = "true" ]; then
if [ "$status_val" != "Connecting" ]; then
echo "### $EH_NAME: SET <$object.Status> <Connecting> ###" > /dev/console
cmclient SETE "$object.Status" "Connecting"
fi
else
if [ "$status_val" != "Disconnected" ]; then
echo "### $EH_NAME: SET <$object.Status> <Disconnected> ###" > /dev/console
cmclient SETE "$object.Status" "Disconnected"
fi
fi
}
update_client_object() {
cmclient -v clientObj GETO  "$object.AssociatedClient.*.[Name=$IFNAME]"
cmclient DEL "$clientObj"
}
eventHandler_l2tpserver_down() {
cmclient -v object GETO "Device.X_ADB_VPN.Server.L2TP.*.[Alias=$LINKNAME]"
if [ "$object" = "" ]; then
exit 0
fi
update_l2tp_server_object
tunnel_update_firewall "del" "$PEERNAME" "$IPREMOTE"
update_ip_obj
}
eventHandler_l2tpserver_down
