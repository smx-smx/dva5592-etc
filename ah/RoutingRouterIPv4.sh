#!/bin/sh
AH_NAME="RouterIPv4"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_ipcalc.sh
table_idx="" # rule table for current object
triggerDNSTest() {
	local objMon
	if [ ${#newDestIPAddress} -eq 0 ]; then
		cmclient -v objMon GETO "Device.X_ADB_InterfaceMonitor.[Enable=true].Group.[Enable=true].Interface.[AdminStatus=Operational].[DetectionMode=DNS].[MonitoredInterface=$newInterface]"
		[ ${#objMon} -ne 0 ] && cmclient SET "$objMon.DNSRestart" "true"
	fi
}
setRouteStatus() {
	local _obj="$1" _status="$2" _cmd="SET" armed
	cmclient -u "${AH_NAME}${obj}" "$_cmd" "$_obj.Status" "$_status"
}
check_rules() {
	[ "$user" = "Refresh" ] && return 0
	local rule
	cmclient -v rule GETO "Device.Routing.Router.1.IPv4Forwarding.[Enable=true].[Status=Disabled]"
	for rule in $rule; do
		[ "$rule" != "$obj" ] && cmclient -u "Refresh" SET "$rule.Enable" "true"
	done
}
get_route_params() {
	local ip="$2" mask="$3" net slash buf
	if [ -z "$ip" ]; then
		buf="default"
	elif [ -z "$mask" ]; then
		buf="$ip"
	else
		help_calc_network net "$ip" "$mask"
		help_mask2cidr slash "$mask"
		buf="$net/$slash"
	fi
	eval $1='$buf'
}
service_route_policy_delete() {
	local buf=$1 policy=$2 mask=$3
	ip route del $buf table $policy
	ip rule del fwmark "$policy/$mask" table "$policy"
}
service_reconf_route() {
	local ipv4obj ipv4addr ipv4netmask ip_enable ip_status client iproute_gw \
		qosRefs _enable
	if [ -z "$newGatewayIPAddress" -a -z "$newInterface" ]; then
		echo "### $AH_NAME: NO GatewayIPAddress nor Interface specified!"
		echo "### $AH_NAME: SET <$obj.Status> <Error> ###"
		setRouteStatus "$obj" "Error"
		return 0
	fi
	[ "$newEnable" = "true" ] && route_cmd="add" || route_cmd="del"
	if [ -z "$newInterface" -o "$newOrigin" = "DHCPv4" ]; then
		cmclient -v ipv4objs GETO "Device.IP.Interface.IPv4Address.[Enable=true]"
		for ipv4obj in $ipv4objs; do
			cmclient -v ipv4addr GETV ${ipv4obj}.IPAddress
			cmclient -v ipv4netmask GETV ${ipv4obj}.SubnetMask
			help_calc_network netaddr1 "$ipv4addr" "$ipv4netmask"
			help_calc_network netaddr2 "$newGatewayIPAddress" "$ipv4netmask"
			if [ "$netaddr1" = "$netaddr2" ]; then
				newInterface=${ipv4obj%%.IPv4Address.*}
				cmclient -u "${AH_NAME}${obj}" SET $obj.Interface $newInterface
				break
			fi
		done
	fi
	if [ -n "$newInterface" ]; then
		cmclient -v ip_enable GETV "$newInterface.Enable"
		cmclient -v ip_status GETV "$newInterface.Status"
	fi
	if [ "$ip_enable" = "true" -a "$ip_status" = "Up" -o "$changedEnable" = "1" -a "$newEnable" = "false" ]; then
		buf_cmd=""
		buf_old=""
		iproute_gw="$newGatewayIPAddress"
		ipauto_gw="$newX_ADB_AutoGateway"
		if [ "$ipauto_gw" = "true" -a -z "$iproute_gw" ]; then
			cmclient -v DHCPObject GETO "$newInterface.IPv4Address.[AddressingType=DHCP]"
			if [ ${#DHCPObject} != 0 ]; then
				cmclient -v iproute_gw GETV "Device.DHCPv4.Client.[Interface=$newInterface].IPRouters"
				cmclient SETE "$obj.GatewayIPAddress" "$iproute_gw"
			else
				cmclient -v isDefault GETV "$newInterface.X_ADB_DefaultRoute"
				if [ $isDefault = "true" ]; then
					router=${obj%.IPv4Forwarding.*}
					cmclient -v iproute_gw GETV "$router.IPv4Forwarding.[DestIPAddress=""].GatewayIPAddress"
					cmclient SETE "$obj.GatewayIPAddress" "$iproute_gw"
				fi
			fi
		fi
		if [ "$route_cmd" = "add" ]; then
			get_route_params buf_cmd "$newDestIPAddress" "$newDestSubnetMask"
			[ "$oldEnable" = "true" ] &&
				get_route_params buf_old "$oldDestIPAddress" "$oldDestSubnetMask"
		else
			get_route_params buf_cmd "$oldDestIPAddress" "$oldDestSubnetMask"
		fi
		[ -n "$iproute_gw" ] && buf_cmd="$buf_cmd via $iproute_gw"
		[ -n "$oldGatewayIPAddress" ] && buf_old="$buf_old via $oldGatewayIPAddress"
		if [ "$newForwardingMetric" != "-1" ]; then
			buf_cmd="$buf_cmd metric $newForwardingMetric"
			[ "$changedForwardingMetric" = "1" -a "$oldForwardingMetric" != "-1" ] &&
				buf_old="$buf_old metric $oldForwardingMetric"
		fi
		if [ "$newX_ADB_MTU" != "-1" ]; then
			buf_cmd="$buf_cmd mtu $newX_ADB_MTU"
			[ "$changedX_ADB_MTU" = "1" -a "$oldX_ADB_MTU" != "-1" ] &&
				buf_old="$buf_old mtu $oldX_ADB_MTU"
		fi
		help_lowlayer_ifname_get ifname "$newInterface"
		if [ -n "$ifname" ]; then
			buf_cmd="$buf_cmd dev $ifname"
			table_idx=$(get_dev_rule_table $newInterface)
			if [ "$changedInterface" = "1" ]; then
				help_lowlayer_ifname_get old_ifname "$oldInterface"
				buf_old="$buf_old dev $old_ifname"
				old_table_idx=$(get_dev_rule_table $oldInterface)
			else
				buf_old="$buf_old dev $ifname"
				old_table_idx="$table_idx"
			fi
		fi
		cmclient -v qosRefs GETO Device.QoS.**.[ForwardingPolicy="$newForwardingPolicy"].[Enable=true]
		if [ -z "$qosRefs" ]; then
			newForwardingPolicy="-1"
			[ $oldForwardingPolicy -ne -1 ] && changedForwardingPolicy=1
		fi
		local RuleStatus
		cmclient -v RuleStatus GETV "$obj.Status"
		if [ "$newForwardingPolicy" = "-1" ]; then
			if [ $changedForwardingPolicy -ne 0 ]; then
				[ -n "$buf_old" -a "$changedEnable" = "0" -a "$user" != "IPIf" ] &&
					service_route_policy_delete "$buf_old" "$oldForwardingPolicy" "$oldX_ADB_ForwardingPolicyMask"
			fi
			if [ "$route_cmd" = "add" ]; then
				if [ "$RuleStatus" = "Enabled" -a -n "$buf_old" -a "$changedEnable" = "0" -a "$user" != "IPIf" -a "$user" != "Refresh" ]; then
					echo "### $AH_NAME: Executing <ip route del $buf_old> ###"
					ip route del $buf_old
					[ -n "$old_table_idx" ] && ip route del $buf_old table $old_table_idx
				fi
				service_reconf_default
			elif [ "$RuleStatus" != "Enabled" ]; then
				return 0
			fi
			result=$(ip route $route_cmd $buf_cmd 2>&1)
			ret=$?
			if [ $ret -eq 0 -a "$route_cmd" = 'del' ]; then
				local lli
				cmclient -v lli GETV $newInterface.X_ADB_ActiveLowerLayer
				[ "${lli%.*}" = "Device.PPP.Interface" ] && table_idx=""
			fi
			if [ -n "$table_idx" -a $ret -eq 0 ]; then
				result=$(ip route $route_cmd $buf_cmd table $table_idx 2>&1)
				ret=$?
				if [ "$ret" -ne 0 -a "$route_cmd" = 'add' ]; then
					case "$result" in
					*"File exists"*)
						echo "ip route add $buf_cmd table $table_idx - ret $ret with msg: $result" >/dev/console
						ret=0
						;;
					*) ip route del "$buf_cmd" ;;
					esac
				fi
			fi
		else
			if [ "$route_cmd" = "add" ]; then
				if [ "$oldForwardingPolicy" = "-1" ]; then
					ip route del $buf_old
					[ -n "$old_table_idx" ] && ip route del $buf_old table $old_table_idx
				fi
				[ -n "$buf_old" -a "$changedEnable" = "0" ] &&
					service_route_policy_delete "$buf_old" "$oldForwardingPolicy" "$newX_ADB_ForwardingPolicyMask"
				service_reconf_default
			elif [ "$RuleStatus" != "Enabled" ]; then
				return 0
			fi
			ip rule "$route_cmd" fwmark "$newForwardingPolicy/$newX_ADB_ForwardingPolicyMask" table "$newForwardingPolicy"
			echo "### $AH_NAME: Executing <ip route $route_cmd $buf_cmd table $newForwardingPolicy> ###"
			result=$(ip route $route_cmd $buf_cmd table $newForwardingPolicy 2>&1)
			ret=$?
		fi
		if [ $ret -ne 0 ]; then
			file_exists=$(help_strstr "$result" "File exists")
			if [ -n "$file_exists" ]; then
				setRouteStatus "$obj" "Disabled"
			else
				setRouteStatus "$obj" "Error"
			fi
			check_rules
		elif [ "$route_cmd" = "add" ]; then
			setRouteStatus "$obj" "Enabled"
			triggerDNSTest
		else
			setRouteStatus "$obj" "Disabled"
			check_rules
		fi
	else
		setRouteStatus "$obj" "Disabled"
	fi
}
service_delete() {
	if [ "$newEnable" = "true" -a "$newStatus" = "Enabled" ]; then
		if [ -z "$newDestIPAddress" ]; then
			buf_cmd="default"
		elif [ -n "$newDestSubnetMask" ]; then
			help_calc_network dest_network "$newDestIPAddress" "$newDestSubnetMask"
			help_mask2cidr subnet_slash "$newDestSubnetMask"
			buf_cmd="$dest_network/$subnet_slash"
		else
			buf_cmd="$newDestIPAddress"
		fi
		[ -n "$newGatewayIPAddress" ] &&
			buf_cmd="$buf_cmd via $newGatewayIPAddress"
		[ "$newForwardingMetric" != "-1" ] &&
			buf_cmd="$buf_cmd metric $newForwardingMetric"
		[ "$newX_ADB_MTU" != "-1" ] &&
			buf_cmd="$buf_cmd mtu $newX_ADB_MTU"
		help_lowlayer_ifname_get ifname "$newInterface"
		if [ -n "$ifname" ]; then
			buf_cmd="$buf_cmd dev $ifname"
			table_idx=$(get_dev_rule_table $newInterface)
		fi
		if [ -n "$buf_cmd" ]; then
			echo "### $AH_NAME: Executing <ip route del $buf_cmd> ###"
			ip route del $buf_cmd
			if [ "$newForwardingPolicy" = "-1" -a -n "$table_idx" ]; then
				ip route del $buf_cmd table "$table_idx"
			elif [ -n "$newForwardingPolicy" -a "$newForwardingPolicy" != "-1" ]; then
				service_route_policy_delete "$buf_cmd" "$newForwardingPolicy" "$newX_ADB_ForwardingPolicyMask"
			fi
		fi
		setRouteStatus "$obj" "Disabled"
		[ "$newOrigin" = "Static" ] && check_rules
	fi
}
service_reconf_default() {
	if [ -z "$newDestIPAddress" ]; then
		local obj_if def_route_if def_routes toChangeRoutes toChangeRoute routeBufDel routeBufAdd \
			routeIP routeMask oldRouteGatewayIPAddress routeMetric routeX_ADB_MTU autoGatewayRoutes
		cmclient -v def_routes GETO "Device.Routing.Router.*.IPv4Forwarding.*.[DestIPAddress=].[Enable=true].[ForwardingPolicy=$newForwardingPolicy]"
		for def_route in $def_routes; do
			cmclient -v def_route_if GETV "$def_route.Interface"
			cmclient -v obj_if GETV "$obj.Interface"
			if [ "$def_route" != "$obj" -a "$def_route_if" = "$obj_if" ]; then
				cmclient SET "$def_route.Enable" "false"
				[ "$newForwardingPolicy" = "-1" ] && ip route del default
			fi
			if [ -n "$newGatewayIPAddress" -a -n "$oldGatewayIPAddress" -a "$newGatewayIPAddress" != "$oldGatewayIPAddress" ]; then
				cmclient -v toChangeRoutes GETO "Device.Routing.Router.1.IPv4Forwarding.[Interface="$obj_if"].[X_ADB_AutoGateway=true].[Enable=true]."
				for toChangeRoute in $toChangeRoutes; do
					cmclient -v routeIP GETV "${toChangeRoute}.DestIPAddress"
					cmclient -v routeMask GETV "${toChangeRoute}.DestSubnetMask"
					cmclient -v oldRouteGatewayIPAddress GETV "${toChangeRoute}.GatewayIPAddress"
					cmclient -v routeMetric GETV "${toChangeRoute}.ForwardingMetric"
					cmclient -v routeX_ADB_MTU GETV "${toChangeRoute}.X_ADB_MTU"
					get_route_params routeBufDel "$routeIP" "$routeMask"
					routeBufDel="$routeBufDel dev $ifname"
					get_route_params routeBufAdd "$routeIP" "$routeMask"
					routeBufAdd="$routeBufAdd via $newGatewayIPAddress"
					[ "$routeMetric" != "-1" ] && routeBufAdd="$routeBufAdd metric $routeMetric"
					[ "$routeX_ADB_MTU" != "-1" ] && routeBufAdd="$routeBufAdd mtu $routeX_ADB_MTU"
					routeBufAdd="$routeBufAdd dev $ifname"
					ip route del $routeBufDel
					ip route add $routeBufAdd
				done
				autoGatewayRoutes="Device.Routing.Router.1.IPv4Forwarding.[Interface="$newInterface"].[X_ADB_AutoGateway=true]"
				cmclient SETE "${autoGatewayRoutes}.GatewayIPAddress ${newGatewayIPAddress}"
			fi
		done
	fi
}
ct_flush() {
	[ ${#newDestIPAddress} -gt 0 ] && [ "$newDestIPAddress" != "0.0.0.0" -a "$newDestSubnetMask" != "0.0.0.0" ] &&
		echo $newDestIPAddress/$newDestSubnetMask >/proc/net/nf_conntrack_flush
}
service_config() {
	[ "$setStatus" = "1" ] && exit 0
	if [ "$changedStaticRoute" = "1" ]; then
		[ "$newStaticRoute" = "false" ] && cmclient SETS "$obj" 0 || cmclient SETS "$obj" 1
	fi
	if [ "$changedEnable" = "1" -o "$newEnable" = "true" ]; then
		service_reconf_route
		help_is_changed Enable DestIPAddress DestSubnetMask GatewayIPAddress Interface ForwardingMetric X_ADB_MTU && ct_flush
	else
		[ -n "$newInterface" ] && triggerDNSTest
	fi
}
case "$op" in
d)
	service_delete
	[ "$newEnable" = "true" ] && ct_flush
	;;
s)
	service_config
	;;
esac
exit 0
