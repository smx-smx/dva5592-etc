#!/bin/sh
#udp:ip-down,ppp,*
#sync:max=1
. /etc/ah/helper_functions.sh
EH_NAME="PPTP Client Down Event"
ip_obj=""
path=""
update_ip_obj() {
	local ipv4_obj
	[ ${#ip_obj} -eq 0 ] && return
	cmclient -v ipv4_obj GETO "$ip_obj.IPv4Address.*.[AddressingType=IPCP]"
	[ -n "$ipv4_obj" ] && cmclient DEL "$ipv4_obj"
	cmclient SET "$ip_obj.Status" "LowerLayerDown"
}
update_pptp_client_object() {
	local enable_val status_val reset_val setm
	setm="$path.LocalIPAddress=	$path.RemoteIPAddress="
	cmclient -v status_val GETV "$path.Status"
	cmclient -v enable_val GETV "$path.Enable"
	cmclient -v reset_val GETV "$path.Reset"
	if [ "$reset_val" = "false" -a "$enable_val" = "true" ]; then
		[ "$status_val" != "Connecting" ] && setm="$setm	$path.Reset=true	$path.Status=Disconnected"
	else
		[ "$status_val" != "Disconnected" ] && setm="$setm	$path.Status=Disconnected"
	fi
	[ "$reset_val" = "true" ] && setm="$setm	$path.Reset=false"
	cmclient SETM "$setm"
}
eventHandler_pptpclient_down() {
	cmclient -v path GETO "Device.X_ADB_VPN.Client.PPTP.*.[Alias=$LINKNAME]"
	[ ${#path} -eq 0 ] && exit 0
	cmclient -v ip_obj GETO "Device.IP.Interface.[LowerLayers,$path]"
	update_ip_obj
	update_pptp_client_object
	cmclient SAVE
}
eventHandler_pptpclient_down
