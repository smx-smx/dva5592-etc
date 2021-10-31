#!/bin/sh
AH_NAME="IP_IPv6"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/IPv6_helper_functions.sh
reconf_6to4() {
	local4=$(cmclient GETV $newX_ADB_6to4AddressSource.IPAddress)
	if [ -n "$local4" ]; then
		sixto4_prefix=$(ipv6_find_6to4_prefix "$local4")
		sixto4_address="$sixto4_prefix::1/16"
		if [ "$newX_ADB_6to4Enable" = "true" ]; then
			ip tunnel add tun6to4 mode sit ttl 64 remote any local "$local4"
			ip link set dev tun6to4 up
			ip -6 addr add "$sixto4_address" dev tun6to4
			ip -6 route add 2000::/3 via ::192.88.99.1 dev tun6to4 metric 1
		else
			ip -6 route flush dev tun6to4
			ip link set dev tun6to4 down
			ip tunnel del tun6to4
		fi
	fi
}
reconf_ulaprefix() {
	oldfullprefix="$oldULAPrefix":"$oldX_ADB_ULASubnet"
	newfullprefix="$newULAPrefix":"$newX_ADB_ULASubnet"
	if [ "$global_ipv6enable" = "true" ]; then
		for ipif in $(cmclient GETO Device.IP.Interface.*.[ULAEnable=true].[IPv6Enable=true].[Enable=true].[X_ADB_Upstream=false]); do
			help_lowlayer_ifname_get lowlayer_ifname "$ipif"
			interface_id=$(ipv6_from_mac_to_id $lowlayer_ifname)
			new_ula_address="$newfullprefix":"$interface_id"
			old_ula_address="$oldfullprefix":"$interface_id"
			if [ -n "$oldULAPrefix" -a -n "$oldX_ADB_ULASubnet" ]; then
				echo "### $AH_NAME: <ip -6 addr del $old_ula_address/64 dev $lowlayer_ifname ###" >/dev/console
				ip -6 addr del "$old_ula_address/64" dev $lowlayer_ifname
			fi
			if [ -n "$newULAPrefix" -a -n "$newX_ADB_ULASubnet" ]; then
				echo "### $AH_NAME: <ip -6 addr add $new_ula_address/64 dev $lowlayer_ifname> ###" >/dev/console
				ip -6 addr add "$new_ula_address/64" dev $lowlayer_ifname
			fi
		done
	fi
}
reconf_ipv6_global() {
	local if status
	ipv6_proc_enable "$global_ipv6enable" "all"
	for ipif in $(cmclient GETO Device.IP.Interface.*.[IPv6Enable=true]); do
		help_lowlayer_ifname_get ifname "$ipif"
		for ipv6_addr in $(cmclient GETO "$ipif.IPv6Address.[Enable=true].[Origin=Static]"); do
			cmclient SET "$ipv6_addr.Enable" "true" >/dev/null
		done
		if [ $(cmclient GETV "$ipif.ULAEnable") = "true" ]; then
			cmclient SET "$ipif.ULAEnable" "true" >/dev/null
		fi
	done
	cmclient SET Device.PPP.Interface.[Enable=true].[IPv6CPEnable=true].Reset true
	[ "$global_ipv6enable" = "true" ] && status="Enabled" || status="Disabled"
	cmclient SETE "$obj.IPv6Status" "$status"
	cmclient SET "Device.RouterAdvertisement.[Enable=true].Enable" true
	/etc/ah/DHCPv6Server.sh init
	cmclient SET "Device.DHCPv6.Client.[Enable=true].Enable" true
	/etc/ah/TR069.sh "IP_IF_CHANGED" "ANY"
}
handle_slaac_enable() {
	local ifname="$1" obj allList ifaceList="" iface newAutoconf="1"
	obj=$(help_obj_from_ifname_get "$ifname")
	help_ip_interface_get allList "$obj"
	for obj in $allList; do
		help_lowlayer_ifname_get iface "$obj"
		[ "$ifname" = "$iface" ] && ifaceList="${ifaceList} ${obj}"
	done
	for iface in $ifaceList; do
		cmclient SETE "${iface}.X_ADB_SLAACEnable" "$newX_ADB_SLAACEnable"
	done
	[ ${#ifname} -ne 0 -a -d "/proc/sys/net/ipv6/conf/$ifname" ] || return
	{ [ "$newX_ADB_SLAACEnable" = "true" ] && echo 1 || echo 0; } \
		>/proc/sys/net/ipv6/conf/$ifname/autoconf
}
handle_ula_enable() {
	local ifname="$1"
	is_wan=$(cmclient GETV "$obj.X_ADB_Upstream")
	if [ "$is_wan" = "true" ]; then
		return
	fi
	ipif_status=$(cmclient GETV "$obj.Status")
	ipv6_enable=$(cmclient GETV "$obj.IPv6Enable")
	if [ "$ipv6_enable" = "true" -a "$ip_enable" = "true" -a "$global_ipv6enable" = "true" ] &&
		[ "$newULAEnable" = "true" -a "$ipif_status" = "Up" ]; then
		ula_cmd="add"
	else
		ula_cmd="del"
	fi
	ulaprefix=$(cmclient GETV Device.IP.ULAPrefix)
	ulasubnet=$(cmclient GETV Device.IP.X_ADB_ULASubnet)
	if [ -n "$ulaprefix" -a -n "$ulasubnet" ]; then
		fullprefix=$ulaprefix:$ulasubnet
		interface_id=$(ipv6_from_mac_to_id "$ip_ifname")
		ula_address="$fullprefix":"$interface_id"
		echo "### $AH_NAME: <ip -6 addr $ula_cmd $ula_address/64 dev $ifname> ###" >/dev/console
		ip -6 addr "$ula_cmd" "$ula_address/64" dev $ifname
	fi
}
service_config() {
	local lower_layer ipv6cp_enable
	case "$obj" in
	"Device.IP")
		global_ipv6enable="$newIPv6Enable"
		if [ "$changedIPv6Status" -eq 1 ]; then
			return
		fi
		if [ "$changedIPv6Enable" -eq 1 ]; then
			reconf_ipv6_global
		fi
		if [ "$changedULAPrefix" -eq 1 -o "$changedX_ADB_ULASubnet" -eq 1 ]; then
			reconf_ulaprefix
		fi
		if [ "$changedX_ADB_6to4Enable" -eq 1 -o "$changedX_ADB_6to4AddressSource" -eq 1 ]; then
			if [ -n "$newX_ADB_6to4AddressSource" ]; then
				reconf_6to4
			fi
		fi
		;;
	*)
		help_lowlayer_ifname_get ip_ifname "$obj"
		ip_enable=$(cmclient GETV "$obj.Enable")
		global_ipv6enable=$(cmclient GETV "Device.IP.IPv6Enable")
		if [ "$changedX_ADB_SLAACEnable" = "1" ]; then
			handle_slaac_enable "$ip_ifname"
		fi
		if [ "$changedULAEnable" = "1" -o "$newULAEnable" = "true" ]; then
			handle_ula_enable "$ip_ifname"
		fi
		if [ "$global_ipv6enable" = "true" -a "$setIPv6Enable" = "1" ]; then
			ipv6_proc_enable "$newIPv6Enable" "$ip_ifname"
			if [ "$changedIPv6Enable" = "1" ]; then
				for ipv6_addr in $(cmclient GETO "$obj.IPv6Address.[Enable=true].[Origin=Static]"); do
					cmclient SET "$ipv6_addr.Enable" "true" >/dev/null
				done
				if [ $(cmclient GETV "$obj.ULAEnable") = "true" ]; then
					cmclient SET "$obj.ULAEnable" "true" >/dev/null
				fi
				cmclient -v lower_layer GETV $obj.LowerLayers
				case "$lower_layer" in
				*"PPP.Interface"*)
					cmclient -v ipv6cp_enable GETV $lower_layer.IPv6CPEnable
					[ "$ipv6cp_enable" = "true" -a "$newIPv6Enable" = "true" ] && cmclient SET $lower_layer.Reset true
					;;
				esac
			fi
		fi
		;;
	esac
}
case "$op" in
s)
	service_config
	;;
esac
exit 0
