#!/bin/sh
AH_NAME="NAT"
[ "$user" = "dummy" ] && exit 0
if [ "$changedEnable" = "1" ]; then
	state="disabled"
	[ "$newEnable" = "true" ] && state="enabled"
	logger -t "cm" -p 7 "LAN: NAT ${state}"
fi
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_ipcalc.sh
if [ "${user%%_*}" = "init" ]; then
	user=${user#init_}
	init=1
fi
get_lan_interface() {
	local qos_classification
	cmclient -v qos_classification GETO Device.QoS.Classification.[ForwardingPolicy=$2]
	for qos_classification in $qos_classification; do
		help_lowlayer_ifname_get $1 "%($qos_classification.Interface)"
		break
	done
}
configure_nat() {
	local enable=$1 ifname ifnames cmd cmdSip IPInterfaces IPInterface IPInterfaceName
	help_lowlayer_ifname_get_all ifnames "$newInterface"
	if [ -z "$ifnames" ]; then
		[ "$enable" = "true" ] && cmclient SETE "$obj.Status" "Error" || cmclient SETE "$obj.Status" "Disabled"
		return
	fi
	if [ ${newX_ADB_ForwardingPolicy:--1} -eq -1 ]; then
		for ifname in $ifnames; do
			help_iptables -t nat -A NATIf.${obj##*.} -o $ifname -j NATIf.${obj##*.}_
		done
	else
		help_iptables -t nat -A NATIf.${obj##*.} -j NATIf.${obj##*.}_
	fi
	if [ ${newX_ADB_ExternalPort:-0} -eq 0 -a -z "$newX_ADB_ExternalIPAddress" \
		-a "${newX_ADB_Type:-"NAPT"}" = "NAPT" -a ${newX_ADB_ForwardingPolicy:--1} -eq -1 ]; then
		[ "$enable" = "true" ] && help_iptables -t nat -A NATIf.${obj##*.}_ -j MASQUERADE
	else
		local icmp_cmd table qos_classification lan_interface rt_op op \
			external_ip_address internal_ip_address internal_ip_mask \
			qos_classification
		if [ ${newX_ADB_ExternalPort:-0} -ne 0 -o -n "$newX_ADB_ExternalIPAddress" ] && [ "$enable" = "true" ]; then
			cmclient -v IPInterfaces GETO Device.IP.Interface.[X_ADB_Upstream=false]
			for IPInterface in $IPInterfaces; do
				help_lowlayer_ifname_get IPInterfaceName "${IPInterface}"
				if iptables -t nat -L NATIpPhone | grep -q IP_PHONE_"$IPInterfaceName"; then
					help_iptables -t nat -D NATIpPhone -j IP_PHONE_"$IPInterfaceName"
					help_iptables -t nat -F IP_PHONE_"$IPInterfaceName"
					help_iptables -t nat -X IP_PHONE_"$IPInterfaceName"
				fi
			done
		fi
		for ifname in $ifnames; do
			case "${newX_ADB_Type:-"NAPT"}" in
			"NAPT")
				cmd=""
				icmp_cmd=""
				if [ ${newX_ADB_ForwardingPolicy:-0} -gt 0 ]; then
					cmd="$cmd -m mark --mark ${newX_ADB_ForwardingPolicy}/$newX_ADB_ForwardingPolicyMask"
					icmp_cmd="$icmp_cmd -m mark --mark ${newX_ADB_ForwardingPolicy}/$newX_ADB_ForwardingPolicyMask"
				fi
				if [ -n "$newX_ADB_ExternalIPAddress" ]; then
					table=1000${newInterface##*.}
					get_lan_interface lan_interface "$newX_ADB_ForwardingPolicy"
					if [ "$enable" = "true" ]; then
						cmclient SET "$newInterface.X_ADB_ProxyArp" true
						ip rule add dev $ifname table $table
						rt_op="add"
					else
						cmclient SET "$newInterface.X_ADB_ProxyArp" false
						ip rule del dev $ifname table $table
						rt_op="del"
					fi
					if [ -z "$newX_ADB_ExternalIPMask" -o "$newX_ADB_ExternalIPMask" = "255.255.255.255" ]; then
						cmd="$cmd -j SNAT --to-source $newX_ADB_ExternalIPAddress"
						icmp_cmd="$icmp_cmd -j SNAT --to-source $newX_ADB_ExternalIPAddress"
						ip route $rt_op $newX_ADB_ExternalIPAddress dev $lan_interface table $table
					else
						help_first_ip startIP $newX_ADB_ExternalIPAddress $newX_ADB_ExternalIPMask
						help_last_ip endIP $newX_ADB_ExternalIPAddress $newX_ADB_ExternalIPMask
						cmd="$cmd -j SNAT --to-source ${startIP}-${endIP}"
						icmp_cmd="$icmp_cmd -j SNAT --to-source ${startIP}-${endIP}"
						ip route $rt_op ${newX_ADB_ExternalIPAddress}/${newX_ADB_ExternalIPMask} dev $lan_interface table $table
					fi
					if [ ${newX_ADB_ExternalPort:-0} -gt 0 ]; then
						cmd="${cmd}:${newX_ADB_ExternalPort}"
						[ ${newX_ADB_ExternalPortEndRange:-0} -gt 0 ] && cmd="${cmd}-${newX_ADB_ExternalPortEndRange}"
					fi
					if [ "$enable" = "true" ]; then
						help_iptables -t nat -A NATIf.${obj##*.}_ -p udp $cmd
						help_iptables -t nat -A NATIf.${obj##*.}_ -p tcp $cmd
						help_iptables -t nat -A NATIf.${obj##*.}_ -p icmp $icmp_cmd
					fi
				else
					if [ "$enable" = "true" ]; then
						cmd="$cmd -j MASQUERADE"
						icmp_cmd=""
						if [ ${newX_ADB_ExternalPort:-0} -gt 0 ]; then
							cmd="${cmd} --to-ports ${newX_ADB_ExternalPort}"
							[ ${newX_ADB_ExternalPortEndRange:-0} -gt 0 ] && cmd="${cmd}-${newX_ADB_ExternalPortEndRange}"
							icmp_cmd="-j MASQUERADE"
						fi
						if [ -z "$icmp_cmd" ]; then
							help_iptables -t nat -A NATIf.${obj##*.}_ $cmd
						else
							help_iptables -t nat -A NATIf.${obj##*.}_ -p tcp $cmd
							help_iptables -t nat -A NATIf.${obj##*.}_ -p udp $cmd
							help_iptables -t nat -A NATIf.${obj##*.}_ -p icmp $icmp_cmd
						fi
					fi
				fi
				;;
			"NAT1:1")
				if [ -z "$newX_ADB_ExternalIPAddress" ]; then
					[ "$enable" = "true" ] && cmclient SETE "$obj.Status" "Error_Misconfigured" || cmclient SETE "$obj.Status" "Disabled"
					return
				fi
				cmd=""
				help_calc_network external_ip_address $newX_ADB_ExternalIPAddress \
					${newX_ADB_ExternalIPMask:-255.255.255.255}
				table=1000${newInterface##*.}
				get_lan_interface lan_interface "$newX_ADB_ForwardingPolicy"
				if [ "$enable" = "true" ]; then
					cmclient SET "$newInterface.X_ADB_ProxyArp" true
					ip rule add dev $ifname table $table
					ip route add ${external_ip_address}/${newX_ADB_ExternalIPMask:-32} dev $lan_interface table $table
					cmclient -v SIPPort GETV Device.Services.VoiceService.1.X_ADB_SIP.LocalPort
					[ ${newX_ADB_ForwardingPolicy:-0} -gt 0 ] && cmdSip="$cmd -m mark --mark ${newX_ADB_ForwardingPolicy}/${newX_ADB_ForwardingPolicyMask} -p udp -m udp --sport $SIPPort"
					cmdSip="$cmdSip -j SNAT --to-source ${external_ip_address}:49152-65535"
					help_iptables -t nat -A NATIf.${obj##*.}_ $cmdSip
					[ ${newX_ADB_ForwardingPolicy:-0} -gt 0 ] && cmdSip="$cmd -m mark --mark ${newX_ADB_ForwardingPolicy}/${newX_ADB_ForwardingPolicyMask} -p udp -m udp --dport $SIPPort -m multiport ! --sports $SIPPort"
					cmdSip="$cmdSip -j SNAT --to-source ${external_ip_address}:49152-65535"
					help_iptables -t nat -A NATIf.${obj##*.}_ $cmdSip
					[ ${newX_ADB_ForwardingPolicy:-0} -gt 0 ] && cmd="$cmd -m mark --mark ${newX_ADB_ForwardingPolicy}/${newX_ADB_ForwardingPolicyMask}"
					cmd="$cmd -j NETMAP --to ${external_ip_address}/${newX_ADB_ExternalIPMask:-32}"
					help_iptables -t nat -A NATIf.${obj##*.}_ $cmd
				else
					cmclient SET "$newInterface.X_ADB_ProxyArp" false
					ip rule del dev $ifname table $table
					ip route del ${external_ip_address}/${newX_ADB_ExternalIPMask:-32} dev $lan_interface table $table
				fi
				cmd=""
				cmclient -v qos_classification GETO Device.QoS.Classification.[ForwardingPolicy=${newX_ADB_ForwardingPolicy}]
				for qos_classification in $qos_classification; do
					cmclient -v internal_ip_address GETV ${qos_classification}.SourceIP
					cmclient -v internal_ip_mask GETV ${qos_classification}.SourceMask
					if [ -n "$internal_ip_address" ]; then
						cmd="-i ${ifname} -d ${external_ip_address}/${newX_ADB_ExternalIPMask:-32} -j NETMAP --to ${internal_ip_address}/${internal_ip_mask:-32}"
						[ "$enable" = "true" ] && op=I || op=D
						help_iptables -t nat -$op PortMapping $cmd
						cmd="-i ${ifname} -d ${internal_ip_address}/${internal_ip_mask:-32} -j ACCEPT"
						help_iptables -t filter -$op ForwardAllow_PortMapping $cmd
						cmd="-o ${ifname} -s ${internal_ip_address}/${internal_ip_mask:-32} -j ACCEPT"
						help_iptables -t filter -$op ForwardAllow_PortMapping $cmd
						break
					fi
				done
				;;
			"None")
				if [ ${newX_ADB_ForwardingPolicy:-0} -gt 0 ]; then
					cmd="-m mark --mark ${newX_ADB_ForwardingPolicy}/${newX_ADB_ForwardingPolicyMask}"
					[ "$enable" = "true" ] && help_iptables -t nat -A NATIf.${obj##*.}_ $cmd -j ACCEPT
				fi
				;;
			*) ;;

			esac
		done
	fi
	[ "$enable" = "true" ] && cmclient SETE "$obj.Status" Enabled || cmclient SETE "$obj.Status" Disabled
}
get_max_order() {
	local var max=0
	for var in ${@#$1}; do
		[ $var -gt $max ] && max=$var
	done
	eval $1=$max
}
service_add() {
	local l o maxOrder=0
	cmclient -v l GETO Device.NAT.InterfaceSetting
	for l in $l; do
		if [ "$l" != "$obj" ]; then
			cmclient -v o GETV "${l}.X_ADB_Order"
			[ ${o:-0} -gt $maxOrder ] && maxOrder=$o
		fi
	done
	cmclient SETE "$obj.X_ADB_Order" $((maxOrder + 1))
	help_iptables -t nat -N NATIf.${obj##*.}
	help_iptables -t nat -I NATIf $((maxOrder + 1)) -j NATIf.${obj##*.}
}
service_delete() {
	local i o maxorder
	configure_nat false
	cmclient -v i GETV "Device.NAT.InterfaceSetting.X_ADB_Order"
	get_max_order maxorder $i
	i=1
	while [ $i -le $maxorder ]; do
		cmclient -v o GETO "Device.NAT.InterfaceSetting.[X_ADB_Order=$i]"
		[ ${#o} -gt 0 -a "$o" != "$obj" -a $i -gt $oldX_ADB_Order ] &&
			cmclient SETE "$o.X_ADB_Order" $((i - 1))
		i=$((i + 1))
	done
	help_iptables -t nat -D NATIf -j NATIf.${obj##*.}
	help_iptables -t nat -F NATIf.${obj##*.}
	help_iptables -t nat -F NATIf.${obj##*.}_
	help_iptables -t nat -X NATIf.${obj##*.}
	help_iptables -t nat -X NATIf.${obj##*.}_
}
service_config() {
	local i _ifname
	if [ "$init" = "1" -o "$user" = "refresh" ] || help_is_changed Enable Interface X_ADB_ExternalIPAddress X_ADB_ExternalIPAddress \
		X_ADB_ExternalPort X_ADB_ExternalPortEndRange X_ADB_ForwardingPolicy X_ADB_ForwardingPolicyMask X_ADB_Type X_ADB_Order; then
		if [ "$changedX_ADB_Order" = "1" ]; then
			help_sort_orders "$obj" "$oldX_ADB_Order" "$newX_ADB_Order" "$AH_NAME" "X_ADB_Order"
			help_iptables -t nat -D NATIf -j NATIf.${obj##*.}
			help_iptables -t nat -I NATIf $newX_ADB_Order -j NATIf.${obj##*.}
		fi
		help_iptables -t nat -F NATIf.${obj##*.}
		help_iptables -t nat -F NATIf.${obj##*.}_
		[ "$changedEnable" != "1" -a "$newEnable" != "true" ] && return
		if is_lan_intf "$newInterface"; then
			[ "$newEnable" = "true" ] && cmclient SETE "$obj.Status" "Error_Misconfigured" || cmclient SETE "$obj.Status" "Disabled"
			return
		fi
		help_lowlayer_ifname_get_all "_ifname" "$newInterface"
		if [ -n "$_ifname" ]; then
			configure_nat "$newEnable"
		else
			[ "$newEnable" = "true" ] && cmclient SETE "$obj.Status" "Error" || cmclient SETE "$obj.Status" "Disabled"
		fi
	fi
}
if [ "$1" = "init" ]; then
	help_iptables -t nat -N NATIf
	help_iptables -t nat -A POSTROUTING -j NATIf
	cmclient -v i GETV "Device.NAT.InterfaceSetting.X_ADB_Order"
	get_max_order maxorder $i
	i=0
	nextorder=1
	while [ $i -lt $maxorder ]; do
		i=$((i + 1))
		cmclient -v obj GETO "Device.NAT.InterfaceSetting.[X_ADB_Order=$i]"
		[ ${#obj} -eq 0 ] && continue
		set -- $obj
		if [ $# -gt 1 ]; then
			echo "Multiple NAT.InterfaceSetting with the same X_ADB_Order ($i) detected. Fix your config!" >/dev/console
			for obj in ${@#$1}; do
				maxorder=$((maxorder + 1))
				cmclient SETE "$obj.X_ADB_Order" "$maxorder"
			done
		fi
		help_iptables -t nat -N NATIf.${1##*.}
		help_iptables -t nat -A NATIf -j NATIf.${1##*.}
		[ $nextorder -ne $i ] && cmclient SETE "$obj.X_ADB_Order" "$nextorder"
		nextorder=$((nextorder + 1))
	done
	cmclient -u "init_${tmpiptablesprefix##*/}" SET "Device.NAT.InterfaceSetting.[Enable=true].Enable" true
fi
case "$op" in
a)
	service_add
	;;
d)
	service_delete
	;;
g)
	for arg; do # Arg list as separate words
		service_get "$obj.$arg"
	done
	;;
s)
	service_config
	if [ "$changedEnable" = "1" -o "$changedInterface" = "1" ]; then
		cmclient -v NATedRelay GETO "Device.DHCPv4.Relay.Forwarding.[Enable=true].[X_ADB_UpstreamInterface=${newInterface}]"
		[ -n "$NATedRelay" ] && cmclient SET "${NATedRelay}.Enable" true
		cmclient SET Device.NAT.PortMapping.[Enable=true].[Interface=$oldInterface].[AllInterfaces=false].Enable true
		cmclient SET Device.NAT.PortMapping.[Enable=true].[AllInterfaces=true].Enable true
		cmclient -v ip GETV $newInterface.[Enable=true].IPv4Address.[Enable=true].IPAddress
		if [ $changedInterface -eq 1 ]; then
			cmclient SET Device.NAT.PortMapping.[Enable=true].[Interface=$newInterface].[AllInterfaces=false].Enable true
			cmclient -v _ip GETV $oldInterface.[Enable=true].IPv4Address.[Enable=true].IPAddress
			ip="$ip $_ip"
		fi
		help_iptables commit
		for ip in $ip; do
			echo $ip >/proc/net/nf_conntrack_flush
		done
	fi
	;;
esac
exit 0
