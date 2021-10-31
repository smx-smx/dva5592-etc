#!/bin/sh
AH_NAME="RouterIPv6"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "eh_ipv6" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize >/dev/null
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/IPv6_helper_functions.sh
reconfig_dependent_forwardings() {
	local each_hop each_obj exclude_obj="$1" dest_pref="$2" dest_iface="$3"
	[ ${#exclude_obj} -eq 0 -o ${#dest_pref} -eq 0 -o ${#dest_iface} -eq 0 ] && return
	cmclient -v each_obj GETO "Device.Routing.Router.*.IPv6Forwarding.[Interface=$dest_iface].[Enable=true]"
	for each_obj in $each_obj; do
		[ "$each_obj" = "$exclude_obj" ] && continue
		cmclient -v each_hop GETV "$each_obj.NextHop"
		[ "$(prefix_from_addr_len $each_hop ${dest_pref##*/})" = "$(prefix_from_addr_len ${dest_pref%%/*} ${dest_pref##*/})" ] &&
			cmclient SET "$each_obj.Enable" "true"
	done
}
service_disable_previous_ipv6_default() {
	local def_route
	cmclient -v def_route GETO "Device.Routing.Router.*.IPv6Forwarding.*.[DestIPPrefix=].[Enable=true]"
	for def_route in $def_route; do
		[ "$def_route" != "$obj" ] && cmclient SET "$def_route.Enable" "false"
	done
}
service_reconf_ipv6_forwarding() {
	local ip_enable ip_status="" lls ll ll_v6_status=""
	if [ ${#newNextHop} -eq 0 -a ${#newInterface} -eq 0 ]; then
		echo "### $AH_NAME: NO GatewayIPAddress nor Interface specified!"
		echo "### $AH_NAME: SET <$obj.Status> <Error_Misconfigured> ###"
		cmclient SET -u "${AH_NAME}${obj}" "$obj.Status" "Error_Misconfigured"
		return 0
	fi
	[ "$newEnable" = "true" ] && route_cmd="add" || route_cmd="del"
	if [ ${#newInterface} -ne 0 ]; then
		cmclient -v ip_enable GETV "$newInterface.Enable"
		cmclient -v ip_status GETV "$newInterface.Status"
		if [ "$ip_status" != "Up" ]; then
			cmclient -v lls GETV "$newInterface.LowerLayers"
			while [ ${#lls} -ne 0 ]; do
				ll=${lls%%,*}
				case $ll in
				"Device.PPP.Interface."*)
					cmclient -v ll_v6_status GETV "$ll.IPv6CP.LocalInterfaceIdentifier"
					[ ${#ll_v6_status} -ne 0 ] && ip_status="Up"
					;;
				esac
				lls=${lls#*,}
				[ "$ll" = "$lls" ] && break
			done
		fi
		help_lowlayer_ifname_get ifname "$newInterface"
	fi
	if [ "$ip_enable" = "true" -a "$ip_status" = "Up" -o ${#newInterface} -eq 0 ]; then
		local buf_cmd="" buf_old=""
		[ ${#newDestIPPrefix} -eq 0 ] && buf_cmd="default" || buf_cmd="$newDestIPPrefix"
		[ ${#oldDestIPPrefix} -eq 0 ] && buf_old="default" || buf_old="$oldDestIPPrefix"
		[ ${#newNextHop} -ne 0 ] && buf_cmd="$buf_cmd via $newNextHop"
		[ ${#oldNextHop} -ne 0 ] && buf_old="$buf_old via $oldNextHop"
		[ "$newForwardingMetric" != "-1" ] && buf_cmd="$buf_cmd metric $newForwardingMetric"
		[ "$oldForwardingMetric" != "-1" ] && buf_old="$buf_old metric $oldForwardingMetric"
		[ ${#ifname} -ne 0 ] && buf_cmd="$buf_cmd dev $ifname" && buf_old="$buf_old dev $ifname"
		if [ "$newForwardingPolicy" = "-1" ]; then
			if [ "$route_cmd" = "add" ]; then
				if [ ${#buf_old} -ne 0 -a "$buf_old" != "$buf_cmd" -a "$changedEnable" -eq 0 -a "$user" != "IPIf" ]; then
					echo "### $AH_NAME: Executing <ip -6 route del $buf_old> ###"
					ip -6 route del $buf_old
				fi
				if [ ${#newDestIPPrefix} -eq 0 ]; then
					service_disable_previous_ipv6_default
				fi
			elif [ "$newStatus" != "Enabled" ]; then
				return 0
			fi
			echo "### $AH_NAME: Executing <ip -6 route $route_cmd $buf_cmd> ###"
			result=$(ip -6 route $route_cmd $buf_cmd 2>&1)
		else
			if [ "$route_cmd" = "add" ]; then
				if [ ${#buf_old} -ne 0 -a "$buf_old" != "$buf_cmd" -a "$changedEnable" -eq 0 -a "$user" != "IPIf" ]; then
					echo "### $AH_NAME: Executing <ip -6 route del $buf_old table $newForwardingPolicy> ###"
					ip -6 route del $buf_old
					result=$(ip -6 route del default table $newForwardingPolicy 2>&1)
					ip -6 rule del fwmark "$newForwardingPolicy"/0xFF table "$newForwardingPolicy"
				fi
				if [ ${#newDestIPPrefix} -eq 0 ]; then
					service_disable_previous_ipv6_default
				fi
			elif [ "$newStatus" != "Enabled" ]; then
				return 0
			fi
			echo "### $AH_NAME: Executing <ip -6 route $route_cmd $buf_cmd table $newForwardingPolicy> ###"
			result=$(ip -6 route $route_cmd $buf_cmd table $newForwardingPolicy 2>&1)
			ip -6 rule "$route_cmd" fwmark "$newForwardingPolicy"/0xFF table "$newForwardingPolicy"
		fi
		ret=$?
		if [ $ret -ne 0 ] && [ "$buf_old" != "$buf_cmd" -o "$route_cmd" != "add" ]; then
			file_exists=$(help_strstr "$result" "File exists")
			if [ ${#file_exists} -ne 0 ]; then
				echo "### $AH_NAME: SET <$obj.Status> <Disabled> ###"
				cmclient SET -u "${AH_NAME}${obj}" "$obj.Status" "Disabled"
			else
				echo "### $AH_NAME: SET <$obj.Status> <Error> ###"
				cmclient SET -u "${AH_NAME}${obj}" "$obj.Status" "Error"
			fi
		elif [ "$route_cmd" = "add" ]; then
			echo "### $AH_NAME: SET <$obj.Status> <Enabled> ###"
			cmclient SET -u "${AH_NAME}${obj}" "$obj.Status" "Enabled"
		else
			echo "### $AH_NAME: SET <$obj.Status> <Disabled> ###"
			cmclient SET -u "${AH_NAME}${obj}" "$obj.Status" "Disabled"
		fi
	else
		echo "### $AH_NAME: SET <$obj.Status> <Disabled> ###"
		cmclient SET -u "${AH_NAME}${obj}" "$obj.Status" "Disabled"
	fi
	if [ ${#newDestIPPrefix} -eq 0 -o "$newDestIPPrefix" = "::/0" ]; then
		cmclient SET "Device.RouterAdvertisement.[Enable=true].Enable true"
	fi
}
service_config() {
	local reconfig_output reconfig_rule=0
	if [ "$changedExpirationTime" = "1" ]; then
		if [ "$newExpirationTime" != "$INFINITE" -a "$newExpirationTime" != "$INDEFINITE" ]; then
			help_ipv6_route_action_timer "ADD" "$obj" "$(help_ipv6_lft_to_secs $newExpirationTime $(date -u +"%s"))"
		elif [ "$oldExpirationTime" != "$INFINITE" -a "$oldExpirationTime" != "$INDEFINITE" ]; then
			help_ipv6_route_action_timer "DEL" "$obj"
		fi
		help_is_changed "Enable" "DestIPPrefix" "ForwardingPolicy" "NextHop" "Interface" "Origin" "ForwardingMetric" || exit 0
	fi
	if [ "$setStatus" = "1" ]; then
		exit 0
	fi
	[ "$setEnable" -eq 1 -o "$setNextHop" -eq 1 -o "$setDestIPPrefix" -eq 1 -o "$setForwardingMetric" -eq 1 ] && reconfig_rule=1
	if [ "$changedEnable" -eq 1 ] || [ "$newEnable" = "true" -a $reconfig_rule -eq 1 ]; then
		service_reconf_ipv6_forwarding
		cmclient SET Device.X_ADB_FastForward.Yatta.FlushConnections true
		cmclient -v reconfig_output GETV "$obj.Status"
		[ "$reconfig_output" = "Enabled" ] && reconfig_dependent_forwardings "$obj" "$newDestIPPrefix" "$newInterface"
	fi
}
service_delete() {
	if [ "$newEnable" = "true" ]; then
		local buf_cmd
		[ ${#newDestIPPrefix} -eq 0 ] && buf_cmd="default" || buf_cmd="$newDestIPPrefix"
		[ ${#newNextHop} -ne 0 ] && buf_cmd="$buf_cmd via $newNextHop"
		[ "$newForwardingMetric" != "-1" ] && buf_cmd="$buf_cmd metric $newForwardingMetric"
		help_lowlayer_ifname_get ifname "$newInterface"
		[ ${#ifname} -ne 0 ] && buf_cmd="$buf_cmd dev $ifname"
		if [ ${#buf_cmd} -ne 0 ]; then
			echo "### $AH_NAME: Executing <ip -6 route del $buf_cmd> ###"
			ip -6 route del $buf_cmd
		fi
		[ ${#newForwardingPolicy} -ne 0 ] && ip route del default table "$newForwardingPolicy"
		cmclient SET -u "${AH_NAME}${obj}" "$obj.Status" "Disabled"
		[ ${#newDestIPPrefix} -eq 0 -o "$newDestIPPrefix" = "::/0" ] && cmclient SET "Device.RouterAdvertisement.[Enable=true].Enable" "true"
	fi
	help_ipv6_route_action_timer "DEL" "$obj"
}
case "$op" in
s)
	service_config
	;;
d)
	service_delete
	cmclient SET Device.X_ADB_FastForward.Yatta.FlushConnections true
	;;
esac
exit 0
