#!/bin/sh
#udp:ip-up,ppp,*
#sync:max=1
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tunnel.sh
EH_NAME="L2TP Server UP Event"
update_ip_obj() {
	local setm_param
	cmclient -v ip_obj GETO "Device.IP.Interface.*.[Name=$IFNAME]"
	if [ "$ip_obj" = "" ]; then
		cmclient -v ip_obj_index ADD "Device.IP.Interface"
		ip_obj="Device.IP.Interface."$ip_obj_index
		echo "### $EH_NAME: SET <$ip_obj.Type> <Tunnel> ###" >/dev/console
		echo "### $EH_NAME: SET <$ip_obj.Name> <$IFNAME> ###" >/dev/console
		cmclient SETM "$ip_obj.Type=Tunnel	$ip_obj.Name=$IFNAME"
	fi
	cmclient -v ipv4_obj GETO "$ip_obj.IPv4Address.*.[AddressingType=IPCP]"
	if [ -z "$ipv4_obj" ]; then
		cmclient -v ipv4_index ADD $ip_obj.IPv4Address
		if [ "$ipv4_index" = "ERROR" ]; then
			echo "$EH_NAME: ERROR adding obj <$ip_obj.IPv4Address>" >/dev/console
			exit 0
		fi
		ipv4_obj=$ip_obj"."IPv4Address"."$ipv4_index
	fi
	echo "### $EH_NAME: SET <$ipv4_obj.IPAddress> <$IPLOCAL> ###" >/dev/console
	setm_param="$ipv4_obj.IPAddress=$IPLOCAL"
	echo "### $EH_NAME: SET <$ipv4_obj.SubnetMask> <255.255.255.255> ###" >/dev/console
	setm_param="$setm_param	$ipv4_obj.SubnetMask=255.255.255.255"
	echo "### $EH_NAME: SET <$ipv4_obj.AddressingType> <IPCP> ###" >/dev/console
	setm_param="$setm_param	$ipv4_obj.AddressingType=IPCP"
	echo "### $EH_NAME: SET <$ipv4_obj.Enable> <true> ###" >/dev/console
	setm_param="$setm_param	$ipv4_obj.Enable=true"
	cmclient SETM "$setm_param"
	echo "### $EH_NAME: SET <$ip_obj.Enable> <true> ###" >/dev/console
	echo "### $EH_NAME: SET <$ip_obj.Status> <Up> ###" >/dev/console
	cmclient SETM "$ip_obj.Enable=true	$ip_obj.Status=Up"
}
update_client_object() {
	cmclient -v clientId ADD "$object.AssociatedClient"
	echo "### $EH_NAME: SET <$object.AssociatedClient.$clientId.LocalIPAddress> <$IPLOCAL> ###" >/dev/console
	cmclient SET "$object.AssociatedClient.$clientId.LocalIPAddress" "$IPLOCAL"
	echo "### $EH_NAME: SET <$object.AssociatedClient.$clientId.RemoteIPAddress> <$IPREMOTE> ###" >/dev/console
	cmclient SET "$object.AssociatedClient.$clientId.RemoteIPAddress" "$IPREMOTE"
	echo "### $EH_NAME: SET <$object.AssociatedClient.$clientId.Name> <$IFNAME> ###" >/dev/console
	cmclient SET "$object.AssociatedClient.$clientId.Name" "$IFNAME"
	cmclient -v status_val GETV "$object.Status"
	if [ "$status_val" != "Connected" ]; then
		echo "### $EH_NAME: SET <$object.Status> <Connected> ###" >/dev/console
		cmclient SET "$object.Status" "Connected"
	fi
}
eventHandler_l2tpserver_up() {
	cmclient -v object GETO "Device.X_ADB_VPN.Server.L2TP.*.[Alias=$LINKNAME]"
	if [ "$object" = "" ]; then
		exit 0
	fi
	tunnel_update_firewall "add" "$PEERNAME" "$IPREMOTE"
	update_ip_obj
}
eventHandler_l2tpserver_up
