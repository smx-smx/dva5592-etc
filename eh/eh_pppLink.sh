#!/bin/sh
#udp:ip-*,ppp,*
#sync:max=3
. /etc/ah/helper_serialize.sh && help_serialize "${LINKNAME}"
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/IPv6_helper_functions.sh
EH_NAME="PPPLink"
case $LINKNAME in
*"PPTP"* | *"L2TP"*) exit 0 ;;
esac
ip_obj=""
is_default=""
NEWLINE='
'
updatePPPObj() {
	echo "### $EH_NAME: SET <$LINKNAME.ConnectionStatus> <Connected> ###" >/dev/console
	cmclient -u "$EH_NAME" SET "$LINKNAME.ConnectionStatus" "Connected"
}
updateIPCPObj() {
	local passthrough="$1"
	local DNSServers
	if [ "$DNS1" = "$DNS2" ]; then
		[ ${#DNS1} -gt 3 -a "$DNS1" != "0.0.0.0" ] && DNSServers="$DNS1"
	else
		[ ${#DNS1} -gt 3 -a "$DNS1" != "0.0.0.0" ] && DNSServers="$DNS1"
		[ ${#DNS2} -gt 3 -a "$DNS2" != "0.0.0.0" ] && DNSServers="${DNSServers:+$DNSServers,}$DNS2"
	fi
	rm -f /tmp/dns/ppp_on_demand_${LINKNAME}
	rm -f /tmp/dns/ppp_on_demand_${LINKNAME}.*
	cmclient -u "$EH_NAME" SETM "${LINKNAME}.IPCP.PassthroughEnable=${passthrough}	${LINKNAME}.IPCP.LocalIPAddress=${IPLOCAL}	${LINKNAME}.IPCP.RemoteIPAddress=${IPREMOTE}	${LINKNAME}.IPCP.DNSServers=${DNSServers}"
}
updateDHCPv4ServerPool() {
	local dhcpObj="$1"
	setm_params="$dhcpObj.MinAddress=$IPLOCAL"
	setm_params="$setm_params	$dhcpObj.MaxAddress=$IPLOCAL"
	setm_params="$setm_params	$dhcpObj.SubnetMask=$subnet_mask"
	if [ "$DNS1" = "" -a "$DNS2" = "" ]; then
		setm_params="$setm_params	$dhcpObj.DNSServers="
	elif [ "$DNS1" != "" -a "$DNS2" = "" ]; then
		setm_params="$setm_params	$dhcpObj.DNSServers=$DNS1"
	elif [ "$DNS1" = "" -a "$DNS2" != "" ]; then
		setm_params="$setm_params	$dhcpObj.DNSServers=$DNS2"
	else
		setm_params="$setm_params	$dhcpObj.DNSServers=${DNS1},${DNS2}"
	fi
	cmclient SETM "$setm_params"
}
updateRoutingRules() {
	local is_default="$1"
	table_idx=$(get_dev_rule_table $ip_obj)
	echo "### $EH_NAME: Adding $IPLOCAL on $IFNAME to table $table_idx" >/dev/console
	ip route add $IPREMOTE dev $IFNAME src $IPLOCAL table $table_idx
	if [ "$is_default" = "false" -a -z "$intfHandled" ]; then
		ip route add default dev $IFNAME via $IPREMOTE table $table_idx
	fi
}
updateRoutingRouter() {
	local is_default_loc="$1"
	cmclient -v ip_router GETV "$ip_obj.Router"
	if [ -z "$ip_router" ]; then
		echo "### $EH_NAME: ADD <Device.Routing.Router>" >/dev/console
		cmclient -v router_index ADD "Device.Routing.Router"
		ip_router="Device.Routing.Router.${router_index}"
		cmclient SET "$ip_router.Enable" "true"
		cmclient SET "$ip_obj.Router" "$ip_router"
	fi
	cmclient -v def_route GETO "$ip_router.IPv4Forwarding.[Interface=$ip_obj].[DestIPAddress=]"
	if [ -z "$def_route" ]; then
		cmclient -v iproute_index ADD "$ip_router.IPv4Forwarding"
		def_route="$ip_router.IPv4Forwarding.$iproute_index"
		echo "### $EH_NAME: ADD <$def_route>" >/dev/console
	fi
	for ip_route in $def_route; do
		echo "### $EH_NAME: SET <$ip_route.GatewayIPAddress> <$IPREMOTE>" >/dev/console
		echo "### $EH_NAME: SET <$ip_route.Interface> <$ip_obj>" >/dev/console
		echo "### $EH_NAME: SET <$ip_route.Origin> <IPCP>" >/dev/console
		setm_params="$ip_route.GatewayIPAddress=$IPREMOTE"
		setm_params="$setm_params	$ip_route.Interface=$ip_obj"
		setm_params="$setm_params	$ip_route.Origin=IPCP"
		local tmp
		cmclient -v tmp GETV $ip_route.X_ADB_AutoGateway
		if [ "$tmp" = "false" ]; then
			echo "### $EH_NAME: SET <$ip_route.StaticRoute> <false>" >/dev/console
			setm_params="$setm_params	$ip_route.StaticRoute=false"
		fi
		if [ "$is_default_loc" = "true" ]; then
			echo "### $EH_NAME: SET <$ip_route.Enable> <true>" >/dev/console
			setm_params="$setm_params	$ip_route.Enable=true"
			cmclient SETM "$setm_params"
		else
			cmclient SETEM "$setm_params"
		fi
	done
}
updateIPInterfaceIPv4Address() {
	if [ -z "$ip_obj" ]; then
		echo "### IP Interface Object Not found ###" >/dev/console
		exit 0
	fi
	cmclient -v ipv4_obj GETO "$ip_obj.IPv4Address.[AddressingType=IPCP]"
	if [ -z "$ipv4_obj" ]; then
		cmclient -v ipv4_index ADDS $ip_obj.IPv4Address
		ipv4_obj="$ip_obj.IPv4Address.$ipv4_index"
		echo "### $EH_NAME: ADDS <$ipv4_obj>" >/dev/console
	fi
	echo "### $EH_NAME: SET <$ipv4_obj.IPAddress> <$IPLOCAL> ###" >/dev/console
	echo "### $EH_NAME: SET <$ipv4_obj.SubnetMask> <$subnet_mask> ###" >/dev/console
	echo "### $EH_NAME: SET <$ipv4_obj.AddressingType> <IPCP> ###" >/dev/console
	echo "### $EH_NAME: SET <$ipv4_obj.Enable> <true> ###" >/dev/console
	setm_params="$ipv4_obj.IPAddress=$IPLOCAL"
	setm_params="$setm_params	$ipv4_obj.SubnetMask=$subnet_mask"
	setm_params="$setm_params	$ipv4_obj.AddressingType=IPCP"
	setm_params="$setm_params	$ipv4_obj.Enable=true"
	cmclient SETM "$setm_params"
}
check_parameter() {
	local temp_field i
	[ -z "$remote_mac" ] && return
	for i in 1 2 3 4 5 6; do
		temp_field=$(echo $remote_mac | cut -d ":" -f$i)
		if [ "${#temp_field}" = "1" ]; then
			temp_field="0"$temp_field
		fi
		new_mac="$new_mac":"$temp_field"
	done
	remote_mac=${new_mac##:}
}
eventHandler_pppLinkUp() {
	cmclient -v ip_obj GETO "Device.IP.Interface.[LowerLayers,$LINKNAME]"
	logger -t "cm" "PPP Interface $IFNAME: Up" -p 6
	help_ipv6_reconf_iface "$IFNAME"
	cmclient -v intfHandled GETO "Device.X_ADB_InterfaceMonitor.[Enable=true].Group.[Enable=true].Interface.[MonitoredInterface=$ip_obj].[Enable=true]"
	updatePPPObj
	subnet_temp=$(ifconfig "$IFNAME")
	subnet_temp="${subnet_temp##*Mask:}"
	subnet_mask="${subnet_temp%%$NEWLINE*}"
	cmclient -v dhcpPassThru_val GETV "$LINKNAME.IPCP.PassthroughEnable"
	cmclient -v obj_dhcpv4ServerPool GETV "$LINKNAME.IPCP.PassthroughDHCPPool"
	if [ "$dhcpPassThru_val" = "true" -a -n "$obj_dhcpv4ServerPool" ]; then
		updateIPCPObj "true"
		updateDHCPv4ServerPool "$obj_dhcpv4ServerPool"
		cmclient -v is_default GETV "$ip_obj.X_ADB_DefaultRoute"
	else
		updateIPCPObj "false"
		cmclient -v is_default GETV "$ip_obj.X_ADB_DefaultRoute"
		[ "$is_default" = "false" -a ${#intfHandled} -ne 0 ] && updateRoutingRouter "$is_default"
		updateIPInterfaceIPv4Address
		[ "$is_default" = "true" ] && updateRoutingRouter "$is_default"
		updateRoutingRules "$is_default"
	fi
	if [ ${#MACREMOTE} -ne 0 -a ${#SES_ID} -ne 0 ]; then
		remote_mac=$(help_lowercase "$MACREMOTE")
		pppoe_session="$SES_ID"
		pppoe_session=$(printf "%d" 0x$pppoe_session)
		read local_mac </sys/class/net/"$DEVICE"/address
		local_mac=$(help_lowercase $local_mac)
		check_parameter
	else
		pppoe_session="0"
	fi
	i="$LINKNAME.PPPoE"
	echo "### $EH_NAME: SET <$i.SessionID> <$pppoe_session> ###" >/dev/console
	echo "### $EH_NAME: SET <$i.X_ADB_DeviceName> <$DEVICE> ###" >/dev/console
	echo "### $EH_NAME: SET <$i.X_ADB_LocalMACAddress> <$local_mac> ###" >/dev/console
	echo "### $EH_NAME: SET <$i.X_ADB_RemoteMACAddress> <$remote_mac> ###" >/dev/console
	setm_params="$i.SessionID=$pppoe_session"
	setm_params="$setm_params	$i.X_ADB_DeviceName=$DEVICE"
	setm_params="$setm_params	$i.X_ADB_LocalMACAddress=$local_mac"
	setm_params="$setm_params	$i.X_ADB_RemoteMACAddress=$remote_mac"
	cmclient -u "$EH_NAME" SETM "$setm_params"
	cmclient -v acs_interface GETV Device.ManagementServer.X_ADB_ConnectionRequestInterface
	if [ "$ip_obj" = "$acs_interface" ]; then
		echo "### $EH_NAME: Updating ACS config ###" >/dev/console
		cmclient -v tmp GETV Device.ManagementServer.X_ADB_ConnectionRequestPort
		cmclient SET Device.ManagementServer.X_ADB_ConnectionRequestPort "$tmp"
	fi
	if [ -f /etc/ah/VoIPNetwork.sh ]; then
		/etc/ah/VoIPNetwork.sh u $ip_obj >/dev/console &
	fi
	cmclient -v upnp_enabled GETV "Device.UPnP.Device.Enable"
	if [ "$upnp_enabled" = "true" ]; then
		cmclient -v upnp_extinf GETV "Device.UPnP.Device.X_ADB_ExternalInterface"
		cmclient -v upnp_extauto GETV "Device.UPnP.Device.X_ADB_AutoExternalInterface"
		if [ "$upnp_extinf" = "$ip_obj" ] ||
			[ "$upnp_extauto" = "true" -a "$is_default" = "true" ]; then
			cmclient SET "Device.UPnP.Device.Enable" "true"
		fi
	fi
	if [ -e /tmp/ppp/${LINKNAME}-AuthProUsed ]; then
		read Auth </tmp/ppp/${LINKNAME}-AuthProUsed
		cmclient -u "$EH_NAME" SET "$LINKNAME.X_ADB_CurrentAuthenticationProtocol" "$Auth"
	fi
	cmclient SAVE
}
link_is_enabled() {
	local tmpEnable
	cmclient -v tmpEnable GETV "${LINKNAME}.Enable"
	[ "$tmpEnable" = "true" ]
}
updatePPPObjDown() {
	echo "### $EH_NAME: SET <$LINKNAME.ConnectionStatus> <Disconnected> ###" >/dev/console
	cmclient -u "$EH_NAME" SET "$LINKNAME.ConnectionStatus Disconnected"
}
updateIPCPObjDown() {
	local passthrough="$1"
	local ip_obj="$2" route ifname dev dst gw
	cmclient -u "$EH_NAME" SETM "${LINKNAME}.IPCP.PassthroughEnable=${passthrough}	${LINKNAME}.IPCP.LocalIPAddress=	${LINKNAME}.IPCP.RemoteIPAddress=	${LINKNAME}.IPCP.DNSServers="
	cmclient -v trigger GETV ${LINKNAME}.ConnectionTrigger
	cmclient -v ifname GETV ${LINKNAME}.Name
	if [ "$trigger" = "OnDemand" -o "$trigger" = "X_ADB_OnClient" ]; then
		. /etc/ah/helper_ipcalc.sh
		while read -r dev dst gw _; do
			[ "$dev" = "$ifname" -a "$gw" = "00000000" ] || continue
			help_int2ip route $((0x$dst))
			break
		done </proc/net/route
		if [ -n "$route" ]; then
			cmclient -v dentries GETV Device.DNS.Relay.X_ADB_DynamicForwardingRule.[Enable=true].[Interface=$ip_obj].X_ADB_InboundInterface
			if [ -z "$dentries" ]; then
				echo "5 * ${route} 10000 * ${ifname}" >/tmp/dns/ppp_on_demand_${LINKNAME}
			else
				for dentry in $dentries; do
					help_lowlayer_ifname_get ifx "$dentry"
					if [ -n "$ifx" ]; then
						echo "5 * ${route} 10000 ${ifx} ${ifname}" >/tmp/dns/ppp_on_demand_${LINKNAME}.${dentry}
					fi
				done
			fi
		fi
	fi
}
updateDHCPv4ServerPoolDown() {
	local dhcpObj="$1"
	setm_params="$dhcpObj.MinAddress="
	setm_params="$setm_params	$dhcpObj.MaxAddress="
	setm_params="$setm_params	$dhcpObj.SubnetMask="
	setm_params="$setm_params	$dhcpObj.DNSServers="
	cmclient SETM "$setm_params"
}
eventHandler_pppLinkDown() {
	local dhcpPassThru_val obj_dhcpv4ServerPool i j
	cmclient -v ip_obj GETO "Device.IP.Interface.[LowerLayers,$LINKNAME]"
	cmclient -v dhcpPassThru_val GETV "$LINKNAME.IPCP.PassthroughEnable"
	cmclient -v obj_dhcpv4ServerPool GETV "$LINKNAME.IPCP.PassthroughDHCPPool"
	logger -t "cm" "PPP Interface $IFNAME: Down" -p 6
	if [ "$dhcpPassThru_val" = "true" -a -n "$obj_dhcpv4ServerPool" ]; then
		updateIPCPObjDown "true" "$ip_obj"
		updateDHCPv4ServerPoolDown "$obj_dhcpv4ServerPool"
	else
		updateIPCPObjDown "false" "$ip_obj"
	fi
	updatePPPObjDown
	cmclient DEL "$ip_obj.IPv4Address.[AddressingType=IPCP]"
	if [ -f /etc/ah/VoIPNetwork.sh ]; then
		/etc/ah/VoIPNetwork.sh u $ip_obj >/dev/console &
	fi
}
if [ "$OP" = "ip-up" ]; then
	[ -s /var/run/ppp-${LINKNAME}.pid -a link_is_enabled ] && eventHandler_pppLinkUp
elif [ "$OP" = "ip-down" ]; then
	eventHandler_pppLinkDown
fi
