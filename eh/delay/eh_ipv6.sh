#!/bin/sh
#ipv6:*
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/helper_serialize.sh
EH_NAME="EH IPv6"
AF_INET6="10"
is_bridged_intf() {
	ipif=""
	local ifa_name="$1"
	help_obj_from_ifname_get_var ifa_obj "$ifa_name"
	cmclient -v global_bridge GETO Device.Bridging.Bridge.**.[LowerLayers="$ifa_obj"]
	if [ -z "$global_bridge" ]; then
		cmclient -v link GETO Device.Ethernet.Link.*.[LowerLayers="$ifa_obj"]
		for link in $link; do
			cmclient -v ipif GETO Device.IP.Interface.*.[LowerLayers="$link"]
			[ -n "$ipif" ] && break
		done
		[ -z "$ipif" ] &&
			cmclient -v ipif GETO Device.IP.Interface.*.[LowerLayers="$ifa_obj"]
	fi
}
is_tunneled_intf() {
	local ifa_name="$1" tun_idx
	ipif=""
	tun_idx=${ifa_name#6rdtun}
	[ ${#tun_idx} -gt 0 -a "$tun_idx" != "$ifa_name" ] &&
		cmclient -v ipif GETV "Device.IPv6rd.InterfaceSetting.$tun_idx.TunneledInterface"
	[ -n "$ipif" ]
}
set_ipv6address_status() {
	local obj=$1
	local ipv6addr_status="Preferred	${obj}.Status=Enabled"
	if [ "$IFA_F_DADFAILED" = "true" ]; then
		ipv6addr_status="Duplicate	$obj.Status=Error"
	elif [ "$IFA_F_TENTATIVE" = "true" ]; then
		ipv6addr_status="Tentative"
	fi
	cmclient -u "eh_ipv6" SETM "$obj.IPAddressStatus=$ipv6addr_status"
}
handle_mo_flags() {
	[ -z "$1" -a -z "$2" ] && return
	[ -n "$1" ] && local ifname="$1" || local ifname="$2"
	local dhcpv6_client_obj is_automode old_enable old_req_addr old_req_pref setm
	help_obj_from_ifname_get_var ifname $ifname
	help_ip_interface_get_first ifname $ifname
	cmclient -v dhcpv6_client_obj GETO "Device.DHCPv6.Client.*.[Interface=$ifname]"
	[ -z "$dhcpv6_client_obj" ] && return
	cmclient -v is_automode GETV "$dhcpv6_client_obj.X_ADB_AutoMode"
	[ "$is_automode" = "false" ] && return
	cmclient -v old_enable GETV "$dhcpv6_client_obj.Enable"
	if [ "$icmpv6_managed" = "true" ]; then
		cmclient -v old_req_addr GETV "$dhcpv6_client_obj.RequestAddresses"
		cmclient -v old_req_pref GETV "$dhcpv6_client_obj.RequestPrefixes"
		[ "$old_req_addr" = "true" -a "$old_req_pref" = "true" -a "$old_enable" = "true" ] && return
		setm="$dhcpv6_client_obj.RequestAddresses=true	$dhcpv6_client_obj.RequestPrefixes=true	$dhcpv6_client_obj.Enable=true"
	elif [ "$icmpv6_other" = "true" ]; then
		! help_is_dhcpv6_client_stateful "$dhcpv6_client_obj" && [ "$old_enable" = "true" ] && return
		setm="$dhcpv6_client_obj.RequestAddresses=false	$dhcpv6_client_obj.RequestPrefixes=true	$dhcpv6_client_obj.Enable=true"
	else
		[ "$old_enable" = "false" ] && return
		setm="$dhcpv6_client_obj.Enable=false"
	fi
	cmclient -u "eh_ipv6_automode" SETM "$setm"
}
cleanup_parent_prefix() {
	local parent_prefix="$1" other_children
	cmclient -v other_children GETO "Device.IP.Interface.IPv6Prefix.[ParentPrefix=$parent_prefix].[Enable=true]"
	[ -n "$other_children" ] && return
	cmclient -u "eh_ipv6" DEL "$parent_prefix"
}
cmclient -v tmp GETV Device.IP.IPv6Enable
if [ "$tmp" = "false" ]; then
	[ "$OP" = "RTMGRP_IPV6_ROUTE" -a "$TYPE" = "RTM_DELROUTE" ] ||
		[ "$OP" = "RTMGRP_IPV6_IFADDR" -a "$TYPE" = "RTM_DELADDR" ] ||
		exit 0
fi
event_group=$OP
event_type=$TYPE
icmpv6_managed=$FLAG_M
icmpv6_other=$FLAG_O
link=""
ipif=""
global_bridge=""
case $event_type in
RTM_DEL*) ;;

*)
	handle_mo_flags "$IFA_IFNAME" "$PREFIX_IFNAME"
	;;
esac
case "$event_group" in
"RTMGRP_IPV6_PREFIX")
	prefix_onlink="false"
	prefix_autoconf="false"
	[ "$icmpv6_managed" = "true" ] && exit 0
	if [ "$event_type" = "RTM_NEWPREFIX" ]; then
		prefix_family=$PREFIX_FAMILY
		prefix_type=$PREFIX_TYPE
		prefix_len=$PREFIX_LEN
		prefix_prefer_lifetime=$PREFERRED_TIME
		prefix_valid_lifetime=$VALID_TIME
		ifa_name=$PREFIX_IFNAME
		is_bridged_intf "$ifa_name"
		prefix_onlink=$IF_PREFIX_ONLINK
		prefix_autoconf=$IF_PREFIX_AUTOCONF
		short_prefix_addr=$PREFIX_ADDRESS
		if [ -z "$global_bridge" -a -n "$ipif" -a "$prefix_family" = "$AF_INET6" -a "$prefix_autoconf" = "true" ]; then
			help_serialize "ipv6prefix" notrap
			current_prefix="$short_prefix_addr/$prefix_len"
			cmclient -v ipv6prefix_obj GETO "$ipif.IPv6Prefix.[Prefix=$current_prefix]"
			for ipv6prefix_obj in $ipv6prefix_obj; do
				break
			done
			if [ "$prefix_valid_lifetime" = "0" ]; then
				[ -n "$ipv6prefix_obj" ] && cmclient DEL "$ipv6prefix_obj"
			else
				ipv6prefix_obj=$(help_ipv6_add_prefix "$current_prefix" "RouterAdvertisement" "$prefix_onlink" "true" "$prefix_prefer_lifetime" "$prefix_valid_lifetime" "$ipv6prefix_obj" "$ipif" "eh_ipv6")
			fi
			help_serialize_unlock "ipv6prefix"
		fi
	fi
	;;
"RTMGRP_IPV6_IFADDR")
	[ "$event_type" = "RTM_NEWADDR" ] && action=add
	[ "$event_type" = "RTM_DELADDR" ] && action=del
	if [ "$IFA_F_DADFAILED" = "true" ]; then
		if_obj="$(help_obj_from_ifname_get $IFA_IFNAME)"
		read mac_addr </sys/class/net/"$IFA_IFNAME"/address
		if [ ${#if_obj} -gt 0 ]; then
			if is_lan_intf "$if_obj" "eh_ipv6"; then
				logger -t "cm" -p 7 "LAN: conflict on IPv6 ${IFA_ADDRESS}"
				lan_wan="LAN"
			else
				lan_wan="WAN"
			fi
			logger -t "IPv6$lan_wan" -p 4 "ARS 1 - Duplicate address detected [${IFA_ADDRESS}/$mac_addr]"
		fi
	fi
	ifa_origin=$IFA_ORIGIN
	prefixlen=$IFA_PREFIXLEN
	ifa_local=$IFA_LOCAL
	ifa_label=$IFA_LABEL
	ifa_acast=$IFA_ANYCAST
	ifa_mcast=$IFA_MULTICAST
	ifa_cstamp=$IFA_CACHEINFO_CSTAMP
	ifa_tstamp=$IFA_CACHEINFO_TSTAMP
	[ $IFA_CACHEINFO_IFA_PREFERED -lt -1 ] && ifa_preferred=0 || ifa_preferred=$IFA_CACHEINFO_IFA_PREFERED
	[ $IFA_CACHEINFO_IFA_VALID -lt -1 ] && ifa_valid=0 || ifa_valid=$IFA_CACHEINFO_IFA_VALID
	short_ifa_addr=$IFA_ADDRESS
	ifa_name=$IFA_IFNAME
	if [ -z "$ifa_name" ]; then
		cmclient -v ifa_name GETO "Device.IP.Interface.IPv6Address.[IPAddress=$short_ifa_addr]"
		help_lowlayer_ifname_get ifa_name "${ifa_name%.IPv6Address.*}"
	fi
	is_bridged_intf "$ifa_name"
	case "$short_ifa_addr" in
	fe80:*) ;;

	*)
		[ "$icmpv6_managed" = "true" ] && icmpv6_skip=1
		;;
	esac
	: ${ifa_origin:=AutoConfigured}
	if [ "$action" = "add" -a -z "$global_bridge" -a -n "$ipif" ]; then
		help_serialize "ipv6prefix" notrap
		cmclient -v ipv6add_obj GETO "$ipif.IPv6Address.[IPAddress=$short_ifa_addr]"
		if [ -n "$ipv6add_obj" ]; then
			cmclient -v ifa_origin GETV "$ipv6add_obj.Origin"
			if [ "$ifa_origin" = "DHCPv6" ]; then
				set_ipv6address_status "$ipv6add_obj"
				help_serialize_unlock "ipv6prefix"
				exit 0
			fi
			if [ "$ifa_origin" = "AutoConfigured" ]; then
				cmclient -v ifp_origin GETV "%(%($ipv6add_obj.Prefix).ParentPrefix).Origin"
				if [ "$ifp_origin" = "PrefixDelegation" ]; then
					set_ipv6address_status "$ipv6add_obj"
					help_serialize_unlock "ipv6prefix"
					exit 0
				fi
			fi
		fi
		if [ -n "$icmpv6_skip" -a -n "$ipv6add_obj" ]; then
			set_ipv6address_status "$ipv6add_obj"
			help_serialize_unlock "ipv6prefix"
			exit 0
		fi
		prefix_val=$(prefix_from_addr_len "$short_ifa_addr" "$prefixlen")
		cmclient -v ipif_prefix GETO "$ipif.IPv6Prefix.*.[Prefix=$prefix_val]"
		case "$prefix_val" in
		fe80:*)
			ipif_prefix=$(help_ipv6_add_prefix "$prefix_val" "WellKnown" "false" "false" "$ifa_preferred" "$ifa_valid" "$ipif_prefix" "$ipif" "eh_ipv6")
			;;
		*)
			cmclient -v static_type GETV "$ipif_prefix.StaticType"
			[ "$static_type" != "Child" -a "$static_type" != "Static" ] &&
				ipif_prefix=$(help_ipv6_add_prefix "$prefix_val" "$ifa_origin" "true" "true" "$ifa_preferred" "$ifa_valid" "$ipif_prefix" "$ipif" "eh_ipv6")
			;;
		esac
		ipv6add_obj=$(help_ipv6_add_address "$short_ifa_addr" "$ipif_prefix" "$ifa_origin" "false" "$ifa_preferred" "$ifa_valid" "$ipv6add_obj" "$ipif" "eh_ipv6")
		set_ipv6address_status "$ipv6add_obj"
		help_serialize_unlock "ipv6prefix"
	fi
	if [ "$action" = "del" -a -z "$global_bridge" -a -n "$ipif" -a ! -f "/tmp/${short_ifa_addr}_${ifa_name}" ]; then
		[ -n "$icmpv6_skip" ] && exit 0
		cmclient -v ipv6 GETO "$ipif.IPv6Address.*.[IPAddress=$short_ifa_addr]"
		for ipv6 in $ipv6; do
			cmclient -v origin GETV "$ipv6.Origin"
			case "$origin" in
			"AutoConfigured")
				cmclient -v ipv6prefixpath GETV $ipv6.Prefix
				cmclient -u "eh_ipv6" DEL $ipv6
				cmclient -v ipv6prefix GETO "$ipv6prefixpath"
				if [ -n "$ipv6prefix" ]; then
					cmclient -v ipv6addr GETO "$ipif.IPv6Address.*.[Prefix=$ipv6prefixpath].[IPAddress!]"
					if [ -z "$ipv6addr" ]; then
						cmclient -v parent_prefix GETV "$ipv6prefixpath.ParentPrefix"
						cmclient -u "eh_ipv6" DEL $ipv6prefixpath
						[ -n "$parent_prefix" ] && cleanup_parent_prefix "$parent_prefix"
					fi
					/etc/ah/DHCPv6Server.sh ifchange "$ipif"
				fi
				;;
			"Static" | "DHCPv6")
				if [ "$ifa_valid" = "0" ]; then
					cmclient -u "eh_ipv6" SET "$ipv6.IPAddressStatus" "Invalid"
				elif [ "$ifa_preferred" = "0" ]; then
					cmclient -u "eh_ipv6" SET "$ipv6.IPAddressStatus" "Deprecated"
				fi
				;;
			esac
		done
	fi
	[ "$action" = "del" -a -z "$global_bridge" -a -n "$ipif" -a -f "/tmp/${short_ifa_addr}_${ifa_name}" ] &&
		rm -f "/tmp/${short_ifa_addr}_${ifa_name}"
	;;
"RTMGRP_IPV6_ROUTE")
	[ "$event_type" = "RTM_NEWROUTE" ] && action=add
	[ "$event_type" = "RTM_DELROUTE" ] && action=del
	family=$RTM_FAMILY
	dstlen=$RTM_DST_LEN
	srclen=$RTM_SRC_LEN
	tos=$RTM_TOS
	table=$RTM_TABLE
	proto=$RTPROT
	rta_priority=$RTA_PRIORITY
	rta_ci_expires=$RTA_CI_EXPIRES
	rta_src=$RTA_SRC
	rta_dst_short=$RTA_DST
	iif_name=$RTA_IIF
	oif_name=$RTA_OIF
	rta_gw_short=$RTA_GATEWAY
	[ -z "$dstlen" ] && dstlen="0"
	if [ "$action" = "add" ]; then
		[ "$oif_name" = "lo" -o -z "$oif_name" ] && exit 0
		case "$proto" in
		"BOOT")
			is_tunneled_intf "$oif_name" || exit 0
			rta_dst_prefix="${rta_dst_short:+$rta_dst_short/$dstlen}"
			case "$rta_dst_prefix" in
			"" | "::/0")
				cmclient -v ipv6fwd GETO Device.Routing.Router.1.IPv6Forwarding.[Interface="$ipif"].[DestIPPrefix="$rta_dst_prefix"].[NextHop="$rta_gw_short"]
				if [ -z "$ipv6fwd" ]; then
					setm_params=""
					cmclient -v ipv6fw_idx ADDS Device.Routing.Router.1.IPv6Forwarding
					ipv6fwd="Device.Routing.Router.1.IPv6Forwarding.$ipv6fw_idx"
					setm_params="$ipv6fwd.Interface=$ipif"
					setm_params="$setm_params	$ipv6fwd.Origin=Static"
					setm_params="$setm_params	$ipv6fwd.ForwardingMetric=$rta_priority"
					if [ "$rta_ci_expires" != "0" ]; then
						curr_sec=$(date -u +"%s")
						rta_ci_expires=$(help_ipv6_lft_from_secs $rta_ci_expires $curr_sec)
						cmclient -u "eh_ipv6${ipv6fwd}" SET "$ipv6fwd.ExpirationTime" "$rta_ci_expires"
					fi
					[ -n "$rta_dst_prefix" ] &&
						setm_params="$setm_params	$ipv6fwd.DestIPPrefix=$rta_dst_prefix"
					setm_params="$setm_params	$ipv6fwd.NextHop=$rta_gw_short"
					setm_params="$setm_params	$ipv6fwd.Status=Enabled"
					setm_params="$setm_params	$ipv6fwd.Enable=true"
					cmclient -u "eh_ipv6" SETM "$setm_params"
					cmclient SET Device.RouterAdvertisement.[Enable=true].Enable true
				fi
				;;
			esac
			;;
		"RA" | "UNSPEC")
			is_bridged_intf "$oif_name"
			[ -z "$ipif" ] && exit 0
			if [ -z "$rta_dst" ]; then
				cmclient -v is_def GETV "$ipif.X_ADB_DefaultRoute"
				if [ "$is_def" = "false" ]; then
					[ "$proto" = "RA" ] && ip -6 route del $rta_dst_prefix
					exit 0
				fi
			fi
			rta_dst_prefix="${rta_dst_short:+$rta_dst_short/$dstlen}"
			cmclient -v ipv6fwd GETO Device.Routing.Router.1.IPv6Forwarding.[Interface="$ipif"].[DestIPPrefix="$rta_dst_prefix"].[NextHop="$rta_gw_short"]
			if [ -z "$ipv6fwd" ]; then
				curr_sec setm_params=""
				cmclient -v ipv6fw_idx ADD Device.Routing.Router.1.IPv6Forwarding
				ipv6fwd="Device.Routing.Router.1.IPv6Forwarding.$ipv6fw_idx"
				setm_params="$ipv6fwd.Interface=$ipif"
				setm_params="$setm_params	$ipv6fwd.Origin=RA"
				setm_params="$setm_params	$ipv6fwd.ForwardingMetric=$rta_priority"
				if [ "$rta_ci_expires" != "0" ]; then
					curr_sec=$(date -u +"%s")
					rta_ci_expires=$(help_ipv6_lft_from_secs $rta_ci_expires $curr_sec)
					cmclient -u "eh_ipv6${ipv6fwd}" SET "$ipv6fwd.ExpirationTime" "$rta_ci_expires"
				fi
				[ -n "$rta_dst_prefix" ] &&
					setm_params="$setm_params	$ipv6fwd.DestIPPrefix=$rta_dst_prefix"
				setm_params="$setm_params	$ipv6fwd.NextHop=$rta_gw_short"
				setm_params="$setm_params	$ipv6fwd.Status=Enabled"
				setm_params="$setm_params	$ipv6fwd.Enable=true"
				cmclient -u "eh_ipv6" SETM "$setm_params"
				if [ "$proto" = "RA" ]; then
					case "$rta_dst_prefix" in
					"" | "::/0")
						cmclient SET Device.RouterAdvertisement.[Enable=true].Enable "true"
						;;
					esac
				fi
			fi
			;;
		"KERNEL")
			is_bridged_intf "$oif_name"
			[ -n "$rta_gw_short" ] && prefix="$rta_gw_short" || prefix="$rta_dst_short"
			[ -z "$ipif" -o -z "$prefix" ] && exit 0
			cmclient -v ro_if GETO Device.Routing.Router.1.IPv6Forwarding.[Interface="$ipif"].[Enable="true"].[Status="Error"].[Origin="Static"]
			for ro_if in $ro_if; do
				cmclient -v next_hop GETV "$ro_if.NextHop"
				case "$next_hop" in
				"$rta_gw_short"*)
					cmclient SET "$ro_if.Enable" true
					;;
				esac
			done
			;;
		esac
	elif [ "$action" = "del" ]; then
		[ "$oif_name" = "lo" ] && exit 0
		rta_dst_prefix="${rta_dst_short:+$rta_dst_short/$dstlen}"
		case "$proto" in
		"BOOT")
			[ ${#oif_name} -eq 0 ] || is_tunneled_intf "$oif_name" || exit 0
			[ ${#rta_dst_prefix} -eq 0 -o "$rta_dst_prefix" = "::/0" ] || exit 0
			cmclient -v ipv6fwd GETO "Device.Routing.Router.1.IPv6Forwarding.*.[DestIPPrefix=$rta_dst_prefix].[NextHop=$rta_gw_short].[Origin=Static]"
			;;
		*)
			cmclient -v ipv6fwd GETO Device.Routing.Router.1.IPv6Forwarding.*.[DestIPPrefix="$rta_dst_prefix"].[NextHop="$rta_gw_short"].[Origin!Static]
			;;
		esac
		if [ -n "$ipv6fwd" ]; then
			link_name=""
			if [ -n "$oif_name" ]; then
				cmclient -v ipv6_if GETV "$ipv6fwd.Interface"
				if [ -n "$ipv6_if" ]; then
					cmclient -v eth_link GETV "$ipv6_if.LowerLayers"
					if [ -n "$eth_link" ]; then
						help_lowlayer_ifname_get link_name "$eth_link"
					fi
				fi
			fi
			if [ "$link_name" = "$oif_name" -o -z "$link_name" ]; then
				cmclient -u "eh_ipv6" DEL $ipv6fwd
				if [ "$proto" = "RA" ]; then
					case "$rta_dst_prefix" in
					"" | "::/0")
						cmclient SET Device.RouterAdvertisement.[Enable=true].Enable "true"
						;;
					esac
				fi
			fi
		fi
		if [ -n "$oif_name" ]; then
			is_bridged_intf "$oif_name"
			[ -n "$rta_gw_short" ] && prefix="$rta_gw_short" || prefix="$rta_dst_short"
			if [ -n "$ipif" -a -n "$prefix" ]; then
				cmclient -v ro_if GETO Device.Routing.Router.1.IPv6Forwarding.*.[Interface="$ipif"].[Enable="true"].[Status="Enabled"].[Origin="Static"]
				for ro_if in $ro_if; do
					cmclient -v next_hop GETV "$ro_if.NextHop"
					case "$next_hop" in
					"$prefix"*)
						cmclient SET "$ro_if.Enable" true
						;;
					esac
				done
			fi
		fi
	fi
	;;
esac
exit 0
