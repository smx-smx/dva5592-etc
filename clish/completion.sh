#!/bin/sh
. /etc/clish/clish-commons.sh
. /etc/clish/clish-permissions.sh
load_completions() {
	local file mask="/etc/clish/comp_*.sh"
	for file in $mask; do
		[ "$file" = "$mask" ] && return
		. "${file}"
	done
}
format_print() {
	local str=""
	local token
	for token in $@; do
		str="${str:+$str }\"${token}(${token})\""
	done
	echo "${str}"
}
format_print_ex() {
	sed 's/ /\\ /; s/\(.\+\)/"\1\(\1\)"/' <<-EOF
		$@
	EOF
}
format_print_obj_with_prop_ex() {
	sed 's/ /\\ /; s/.*;$//; s/\(.\+\)\..*;\(.*\)/"\2\(\1\)"/' <<-EOF
		$@
	EOF
}
iface_get_alias_or_ipaddr_with_prefix() {
	local ip_obj="$1"
	local alias_name ipaddr subnet
	cmclient -v objs GETO "${ip_obj}"
	for o in $objs; do
		cmclient -v alias_name GETV "$o.Alias"
		format_print_ex "$alias_name"
		cmclient -v ipaddr GETV "$o.IPAddress"
		cmclient -v subnet GETV "$o.SubnetMask"
		[ -n "$ipaddr" -a "$subnet" ] && format_print_ex "$ipaddr/$(ipv4_mask2prefix $subnet)"
	done
}
iface_get_alias_or_ip6addr_with_prefixlen() {
	local ip_obj="$1"
	local alias_name ip6addr prefix prefixlen objs o
	cmclient -v objs GETO "${ip_obj}"
	for o in $objs; do
		cmclient -v alias_name GETV "$o.Alias"
		format_print_ex "$alias_name"
		cmclient -v ip6addr GETV "$o.IPAddress"
		cmclient -v prefix GETV "%($o.Prefix).Prefix"
		prefixlen=${prefix#*/}
		[ -n "$ip6addr" -a "$prefixlen" ] && format_print_ex "$ip6addr/$prefixlen"
	done
}
generic_list_add() {
	local all_list cur_list
	cmclient -v all_list GETV "$1"
	all_list="$(list_print $all_list)"
	if [ -n "$2" ]; then
		cmclient -v cur_list GETV "$2"
		[ -n "$cur_list" ] && all_list="$(list_exclude $cur_list $all_list)"
	fi
	echo "$all_list"
}
ip6_show_prefix() {
	local this="$1"
	local pr
	cmclient -v pr GETV "$this.Prefix"
	echo "$pr($this)"
}
ip6_prefix_dhcp_iana_manual() {
	local this="$(cli_or_tr_alias_to_tr_obj $1)"
	local iface list item type old_list
	cmclient -v old_list GETV "$this.IANAManualPrefixes"
	cmclient -v iface GETV "$this.Interface"
	for type in Static Child; do
		cmclient -v list GETO "$iface.IPv6Prefix.*.[StaticType=${type}]"
		for item in $list; do
			help_is_in_list "$old_list" "$item" || ip6_show_prefix "$item"
		done
	done
}
ip6_prefix_dhcp_iapd_manual() {
	local this="$(cli_or_tr_alias_to_tr_obj $1)"
	local iface list item type old_list list_all
	cmclient -v old_list GETV "$this.IAPDManualPrefixes"
	cmclient_GETO_Access list "Device.IP.Interface" 1
	for iface in $list; do
		is_lowlevel_upstream "$iface" || continue
		for type in Static PrefixDelegation; do
			local prefix_list
			cmclient -v prefix_list GETO "$iface.IPv6Prefix.*.[Origin=${type}]"
			for item in $prefix_list; do
				help_item_add_uniq_in_list list_all "$list_all" "$item"
			done
		done
	done
	cmclient -v iface GETV "$this.Interface"
	for type in Static Child; do
		cmclient -v list GETO "$iface.IPv6Prefix.*.[StaticType=${type}]"
		for item in $list; do
			help_item_add_uniq_in_list list_all "$list_all" "$item"
		done
	done
	for item in $(list_print $list_all); do
		help_is_in_list "$old_list" "$item" || ip6_show_prefix "$item"
	done
}
get_tr_obj_list_by_ref_prop() {
	local objs_and_vals
	local ref_param
	local val ov
	local values_merged
	local par
	values_merged=""
	for par; do
		cmclient -v objs_and_vals GET "${par%#*}"
		ref_param=${par##*#}
		for ov in $objs_and_vals; do
			cmclient -v val GETV "${ov##*;}.$ref_param"
			values_merged="$values_merged
${ov%;*};$val"
		done
	done
	format_print_obj_with_prop_ex "$values_merged"
}
get_upper_interfaces_obj_by_alias() {
	cmclient -v OBJ GETO "$1"
	if [ -n "$OBJ" ]; then
		objs=$(upper_interfaces_get "$OBJ" "$2")
		for o in $objs; do
			cmclient -v v GET "$o.Alias"
			values="${values}\"${v#*;}(${v%.*;*})\"\n"
		done
	fi
	printf "$values"
}
list_add() {
	format_print "$(generic_list_add $*)"
}
fw_remove_tcp_flag() {
	format_print "$(list_print $(fw_tcp_flags_used $1))"
}
get_alg_list() {
	local algs sep alg out obj
	out=''
	cmclient -v algs GET Device.QoS.App.ProtocolIdentifier
	for obj in $algs; do
		sep='.ProtocolIdentifier;'
		alg=${obj#*"$sep"}
		obj=${obj%%"$sep"*}
		sep='urn:dslforum-org:'
		case $alg in
		*$sep*)
			alg=${alg#*"$sep"}
			;;
		*)
			die "Error getting alg list"
			;;
		esac
		if [ -z "$out" ]; then
			out="$alg($obj)"
		else
			out="$out $alg($obj)"
		fi
	done
	echo "$out"
}
get_forwarding_policies_core() {
	local out_str=""
	local policyHashList=""
	local qos_prefix=""
	local fwd_policy
	local fwd_policies
	local skip_new="$1"
	local filter="$2"
	local filter_include="$3"
	local val
	shift 3
	[ "$filter" != "-" ] && cmclient -v filter GETV "$filter"
	for obj_type; do
		qos_prefix=${obj_type##*\^}
		[ -n "$qos_prefix" ] && qos_prefix=$qos_prefix-
		obj_type=${obj_type%\^*}
		qos_param=${obj_type##*\.}
		qos_query=${obj_type%\.*}
		cmclient -v qos_objects GETO $qos_query
		for qos_object in $qos_objects; do
			if [ "$obj_type" = "Device.QoS.DefaultForwardingPolicy" -o "$obj_type" = "Device.QoS.DefaultTrafficClass" ]; then
				alias="default"
			else
				cmclient -v alias GETV "$qos_object.Alias"
			fi
			cmclient -v fwd_policies GETV "$qos_object.$qos_param"
			fwd_policies="$fwd_policies,"
			while [ -n "$fwd_policies" ]; do
				fwd_policy=${fwd_policies%%","*}
				fwd_policies=${fwd_policies#*","}
				if [ "$filter" != "-" ]; then
					if [ "$filter_include" = "true" ]; then
						case ,"$filter", in
						*,"$fwd_policy",*)
							help_remove_from_unique_list filter "$filter" "$fwd_policy"
							;;
						*)
							fwd_policy=""
							;;
						esac
					else
						case ,"$filter", in
						*,"$fwd_policy",*)
							fwd_policy=""
							;;
						*) ;;
						esac
					fi
				fi
				[ "$fwd_policy" = "0" -o "$fwd_policy" = "" -o "$fwd_policy" = "-1" ] && continue
				local policyHashEntryName="policyHashEntry$fwd_policy"
				if [ "${policyHashList%%*$policyHashEntryName*}" != "$policyHashList" ]; then
					eval $policyHashEntryName=\"\$$policyHashEntryName,$qos_prefix$alias\"
				else
					policyHashList="$policyHashList $policyHashEntryName"
					eval $policyHashEntryName='\"'\"$fwd_policy[$qos_prefix$alias\"
				fi
			done
		done
	done
	for forwardingPolicy in $policyHashList; do
		eval entryString=\$$forwardingPolicy
		extr_fwd_policy=${entryString%%\[*}
		extr_fwd_policy=${extr_fwd_policy#\"*}
		if [ -z "$out_str" ]; then
			out_str="$entryString]($extr_fwd_policy)\""
		else
			out_str="$out_str
$entryString]($extr_fwd_policy)\""
		fi
	done
	if [ "$skip_new" = "false" ]; then
		if [ -z "$out_str" ]; then
			out_str="\"new(new)\""
		else
			out_str="$out_str
\"new(new)\""
		fi
	fi
	if [ "$filter" != "-" -a "$filter_include" = "true" ]; then
		filter="$filter,"
		while [ -n "$filter" ]; do
			val=${filter%%","*}
			if [ -z "$out_str" ]; then
				out_str="\"$val[new]($val)\""
			else
				out_str="$out_str
\"$val[new]($val)\""
			fi
			filter=${filter#*","}
		done
	fi
	echo "$out_str"
}
get_forwarding_policies() {
	get_forwarding_policies_core "false" "-" "-" Device.QoS.Classification.ForwardingPolicy^ Device.QoS.App.DefaultForwardingPolicy^ Device.QoS.DefaultForwardingPolicy^
}
get_forwarding_policies_qos() {
	get_forwarding_policies_core "false" "-" "-" Device.Firewall.Chain.Rule.X_ADB_ForwardingPolicy^fwall Device.NAT.InterfaceSetting.X_ADB_ForwardingPolicy^nat \
		Device.NAT.PortMapping.X_ADB_ForwardingPolicy^portmapping Device.Routing.Router.IPv4Forwarding.ForwardingPolicy^v4route \
		Device.Routing.Router.IPv6Forwarding.ForwardingPolicy^v6route
}
get_traffic_class() {
	get_forwarding_policies_core "false" "-" "-" Device.QoS.Queue.TrafficClasses^
}
get_traffic_class_for_queue() {
	local cur_obj=${1:--}
	get_forwarding_policies_core "false" "$cur_obj" "false" Device.QoS.Classification.TrafficClass^ Device.QoS.App.DefaultTrafficClass^ Device.QoS.DefaultTrafficClass^
}
get_traffic_class_for_selected_queue() {
	local cur_obj=${1:--}
	get_forwarding_policies_core "true" "$cur_obj" "true" Device.QoS.Classification.TrafficClass^ Device.QoS.App.DefaultTrafficClass^ Device.QoS.DefaultTrafficClass^
}
get_vlanIDs() {
	bridge_object="$1"
	cmclient GETV ${bridge_object}.VLAN.VLANID
}
generic_list() {
	local cur_list str
	cmclient -v cur_list GETV "$1"
	set -f
	IFS=","
	set -- $cur_list
	unset IFS
	set +f
	for token; do
		str="${str:+$str }\"${token#X_ADB_}(${token})\""
	done
	echo "$str"
}
extPortList() {
	local a b proto token result
	local obj="$1"
	local prefix="$2"
	cmclient -v a GETV ${obj}.ExternalPort
	if [ -n "$a" -a "$a" != "0" ]; then
		cmclient -v proto GETV ${obj}.Protocol
		cmclient -v b GETV ${obj}.ExternalPortEndRange
		[ "$b" = "0" ] && b=
		token="$proto:${a}${b:+-$b}"
		result="\"${token#X_ADB_}($token)\""
	fi
	printf "$result\n"
	generic_list ${obj}.${prefix}AdditionalExternalPort
}
FacilityActionArgument_complete() {
	cmclient -v objs GETO Device.Services.VoiceService.1.VoiceProfile.*.Line
	for o in $objs; do
		cmclient -v number GETV "$o.DirectoryNumber"
		echo -n "$number($o) "
	done
	echo "Unset(0)"
}
vlans_available() {
	bridge_obj="$1"
	cmclient -v bridge_type GETV $bridge_obj.Standard
	case $bridge_type in
	802.1Q*)
		cmclient -v vlanIDs GET $bridge_obj.VLAN.VLANID
		format_print_obj_with_prop_ex "$vlanIDs"
		;;
	*)
		echo "0(0)"
		;;
	esac
}
get_deref_obj_alias() {
	local obj_list obj alias
	cmclient -v obj_list GETO "$1"
	for obj in $obj_list; do
		cmclient -v alias GETV "%($obj.MonitorInterface).Alias"
		alias=$(echo "$alias" | sed 's/ /\\ /g')
		echo "$alias($obj)"
	done
}
get_cust_obj_by_prop_with_pref() {
	local args="$1" cust="$2" addpref="$3"
	local token objs alias output obj obj_pref base_alias pref=""
	set -f
	IFS="#"
	set -- $args
	unset IFS
	set +f
	for token; do
		alias=${token#*"^"}
		obj=${token%%"^"*}
		[ "$obj" = "$alias" ] && alias="" || token="$obj"
		cmclient -v objs GET "$token"
		if [ -n "$objs" ] && [ "$addpref" = "true" -o "$obj" != "$alias" ]; then
			base_alias="$alias"
			output=""
			while read obj; do
				alias=${obj#*";"}
				obj_pref="$obj"
				[ -n "$base_alias" ] && obj_pref="$alias" && cmclient -v alias GETV "$alias.$base_alias"
				if [ "$addpref" = true ]; then
					case $obj_pref in
					Device.Bridging.Bridge*)
						pref=${obj_pref#*"Device.Bridging.Bridge."}
						pref=${pref%%"."*}
						pref="Bridge.$pref."
						;;
					Device.QoS.*)
						pref=${obj_pref#*"Device.QoS."}
						pref=${pref%%"."*}
						pref="$pref."
						;;
					*)
						pref=${obj_pref#*"Device."}
						pref=${pref%%"."*}
						pref="$pref."
						;;
					esac
				fi
				obj=${obj%%";"*}
				if [ -z "$output" ]; then
					output="$obj;$pref$alias"
				else
					output="$output
$obj;$pref$alias"
				fi
			done <<EOF
$objs
EOF
			format_print_obj_with_prop_ex "$output"
		else
			format_print_obj_with_prop_ex "$objs"
		fi
	done
	if [ -n "$cust" -a "$cust" != "#" ]; then
		set -f
		IFS="#"
		set -- $cust
		unset IFS
		set +f
		for token; do
			echo "\"$token\""
		done
	fi
}
get_mday_list() {
	local list
	local obj="$1"
	local field="$2"
	local skip
	cmclient -v list GETV "$obj.$field"
	for i in $(seq 1 31); do
		if help_is_in_list "$list" "$i"; then
			[ "$3" = "true" ] && skip="false" || skip="true"
		else
			[ "$3" = "true" ] && skip="true" || skip="false"
		fi
		if [ "$skip" = "false" ]; then
			echo "$i($i)"
		fi
	done
}
get_wday_list() {
	local list
	local day
	local obj="$1"
	local field="$2"
	local skip
	cmclient -v list GETV "$obj.$field"
	for i in $(seq 1 7); do
		if help_is_in_list "$list" "$i"; then
			[ "$3" = "true" ] && skip="false" || skip="true"
		else
			[ "$3" = "true" ] && skip="true" || skip="false"
		fi
		if [ "$skip" = "false" ]; then
			case $i in
			1) day="Monday" ;;
			2) day="Tuesday" ;;
			3) day="Wednesday" ;;
			4) day="Thrusday" ;;
			5) day="Friday" ;;
			6) day="Saturday" ;;
			7) day="Sunday" ;;
			esac
			echo "$day($i)"
		fi
	done
}
possible_user_type_to_switch() {
	local loggedName=$USER
	local changedName
	cmclient -v changedName GETV "${1:?'possible_user_type_to_switch - user to modify must be set'}.Username"
	local loggedType
	local changedType
	get_user_role loggedType
	cmclient -v changedType GETV "${1}.X_ADB_Role"
	if [ "$loggedName" = "$changedName" ]; then
		format_print "$loggedType"
	elif [ "$loggedType" = "NormalUser" ]; then
		if [ "$changedType" = "NormalUser" ]; then
			format_print "NormalUser"
		fi
	elif [ "$loggedType" = "PowerUser" ]; then
		if [ "$changedType" != "AdminUser" ]; then
			format_print "NormalUser"
			format_print "PowerUser"
		fi
	elif [ "$loggedType" = "AdminUser" ]; then
		format_print "NormalUser"
		format_print "PowerUser"
		format_print "AdminUser"
	else
		echo "#ERROR unexpected X_ADB_Role=$loggedType of logged user $loggedName"
		exit 1
	fi
}
possible_user_to_modify() {
	local loggedType
	get_user_role loggedType
	if [ "$loggedType" = "NormalUser" ]; then
		local normalUsers
		cmclient -v normalUsers GET "Device.Users.User.[X_ADB_Role=NormalUser].Username"
		for user in $normalUsers; do
			format_print_obj_with_prop_ex $user
		done
	elif [ "$loggedType" = "PowerUser" ]; then
		local normalUsers
		local powerUsers
		cmclient -v normalUsers GET "Device.Users.User.[X_ADB_Role=NormalUser].Username"
		cmclient -v powerUsers GET "Device.Users.User.[X_ADB_Role=PowerUser].Username"
		for user in $normalUsers $powerUsers; do
			format_print_obj_with_prop_ex $user
		done
	elif [ "$loggedType" = "AdminUser" ]; then
		local allUsers
		cmclient -v allUsers GET "Device.Users.User.Username"
		for user in $allUsers; do
			format_print_obj_with_prop_ex $user
		done
	else
		echo "#ERROR unexpected X_ADB_Role of logged user $logged"
		exit 1
	fi
}
possible_user_to_unlock() {
	local normalUsers="" powerUsers="" allUsers="" user username loggedType
	get_user_role loggedType
	case "$loggedType" in
	AdminUser) cmclient -v allUsers GETV "Device.Users.User.Username" ;;
	NormalUser) cmclient -v normalUsers GETV "Device.Users.User.[X_ADB_Role=NormalUser].Username" ;;
	PowerUser)
		cmclient -v normalUsers GETV "Device.Users.User.[X_ADB_Role=NormalUser].Username" # continuation below
		cmclient -v powerUsers GETV "Device.Users.User.[X_ADB_Role=PowerUser].Username"
		;;
	*) exit 1 ;;
	esac
	for username in $normalUsers $powerUsers $allUsers; do
		cmclient -v user GET Device.UserInterface.X_ADB_FailLog.User.[Username=$username].[Locked=true].Username
		[ -n "$user" ] && format_print_obj_with_prop_ex "$user"
	done
}
possible_user_to_del() {
	local loggedUser
	local loggedType
	get_user_role loggedType
	cmclient -v loggedUser GET Device.Users.User.[Username=$USER].Username
	if [ "$loggedType" = "NormalUser" ]; then
		local normalUsers
		cmclient -v normalUsers GET "Device.Users.User.[X_ADB_Role=NormalUser].Username"
		normalUsers=${normalUsers/$loggedUser/}
		for user in $normalUsers; do
			format_print_obj_with_prop_ex $user
		done
	elif [ "$loggedType" = "PowerUser" ]; then
		local normalUsers
		local powerUsers
		cmclient -v normalUsers GET "Device.Users.User.[X_ADB_Role=NormalUser].Username"
		cmclient -v powerUsers GET "Device.Users.User.[X_ADB_Role=PowerUser].Username"
		powerUsers=${powerUsers/$loggedUser/}
		for user in $normalUsers $powerUsers; do
			format_print_obj_with_prop_ex $user
		done
	elif [ "$loggedType" = "AdminUser" ]; then
		local allUsers
		cmclient -v allUsers GET "Device.Users.User.Username"
		allUsers=${allUsers/$loggedUser/}
		for user in $allUsers; do
			format_print_obj_with_prop_ex $user
		done
	else
		echo "#ERROR unexpected X_ADB_Role of logged user $logged"
		exit 1
	fi
}
get_host_list() {
	local host_source_info="$1" hosts host hostname ip_address mac_address
	cmclient -v hosts GETO Device.Hosts.Host
	for host in $hosts; do
		cmclient -v hostname GETV "$host.HostName"
		cmclient -v ip_address GETV "$host.IPAddress"
		cmclient -v mac_address GETV "$host.PhysAddress"
		case "$host_source_info" in
		"hostname")
			echo "$hostname($ip_address)"
			;;
		"ip")
			echo "$ip_address($ip_address)"
			;;
		"mac")
			echo "$mac_address($ip_address)"
			;;
		*)
			echo "$hostname($ip_address)"
			echo "$mac_address($ip_address)"
			echo "$ip_address($ip_address)"
			;;
		esac
	done
}
get_ip_ifaces() {
	local out="*(*)"
	local i
	cmclient -v ifaces GETO Device.IP.Interface.[X_ADB_Permissions="333"]
	for i in $ifaces; do
		help_lowlayer_ifname_get iface $i
		out="$out $iface($iface)"
	done
	echo $out
}
get_ifaces_group() {
	local _obj=$1
	local _on=$2
	local _iflist
	local i
	local j
	cmclient -v ifaces GETO $_obj.[Status=Up]
	for i in $ifaces; do
		help_lowlayer_ifname_get _iface $i
		for j in $_on; do
			if [ "$_iface" = "$j" ]; then
				_iflist="$_iflist$_iface "
			fi
		done
	done
	[ -z "$_iflist" ] && _iflist=none
	set $_iflist
	[ $# -gt 1 ] && _iflist="$_iflist all"
	echo "$_iflist"
}
get_ifaces_groups() {
	local activeif=$(ifconfig | sed 's/[ \t].*//;/^$/d')
	local obj=$3
	local query=""
	[ -z "$obj" ] && echo any && return
	case $obj in
	ATM | PTM)
		query=Device.$obj.Link
		;;
	WiFi)
		query=Device.$obj.Radio
		;;
	VLAN)
		query=Device.Ethernet.${obj}Termination
		;;
	SSID)
		query=Device.WiFi.$obj
		;;
	*)
		query=Device.$obj.Interface
		;;
	esac
	get_ifaces_group "$query" "$activeif"
}
get_syslog_identities() {
	local out="*(*)"
	local i
	cmclient -v ident GETV Device.X_ADB_SystemLog.Service.Identity
	for i in $ident; do
		out="$out $i"
	done
	echo $out
	format_print $*
}
ifname_ifconfig() {
	cd /sys/class/net
	format_print * "all" $*
	cd - >/dev/null
}
ifname_byObjects() {
	local ifObjects objectType singleObject objectInstances ifname
	ifObjects="Device.Bridging.Bridge.Port.[ManagementPort=true] Device.Ethernet.Interface Device.Ethernet.VLANTermination Device.PPP.Interface Device.WiFi.SSID"
	for objectType in $ifObjects; do
		cmclient -v objectInstances GETO $objectType
		for singleObject in $objectInstances; do
			help_lowlayer_ifname_get ifname $singleObject
			echo "$ifname($singleObject)"
		done
	done
	format_print "all" $*
}
get_current_channel_list() {
	local wlan
	cmclient -v wlan GETV "Device.WiFi.Radio.[OperatingFrequencyBand=5GHz].Name"
	for wlan in $wlan; do break; done
	if [ ${#wlan} -gt 0 ]; then
		wlctl -i $wlan channels
	else
		echo "No channels available. 5GHz radio not found."
	fi
}
get_ipsec_protcols() {
	local ah_support
	cmclient -v ah_support GETV Device.IPsec.AHSupported
	[ "$ah_support" = "true" ] && echo "AH(AH)"
	echo "ESP(ESP)"
}
get_time_zones() {
	local time_zone_obj_list i offset area city tzstring
	cmclient -v time_zone_obj_list GETO "Device.Time.X_ADB_AvailableTimeZone.Location."
	for i in $time_zone_obj_list; do
		cmclient -v offset GETV "$i.Offset"
		cmclient -v area GETV "$i.Area"
		cmclient -v city GETV "$i.City"
		cmclient -v tzstring GETV "$i.TzString"
		echo "\"$offset $area/$city($tzstring)\""
	done
	echo "new"
}
get_local_address_obj() {
	local out br_obj eth_link eth_object
	cmclient -v br_objs GETO "Device.Bridging.Bridge"
	for br_obj in $br_objs; do
		cmclient -v eth_links GETO "Device.Ethernet.Link.[LowerLayers=${br_obj}.Port.1]"
		for eth_link in $eth_links; do
			cmclient -v eth_objects GETO "Device.IP.Interface.[LowerLayers=${eth_link}]"
			for eth_object in $eth_objects; do
				cmclient -v ip_objects GETO "$eth_object.IPv4Address"
				for ip_object in $ip_objects; do
					cmclient -v ip_address GETV "$ip_object.IPAddress"
					cmclient -v obj_with_ip_address GETO "Device.X_ADB_SDN.Service.[LocalIPAddress=$ip_object]"
					[ -z "$obj_with_ip_address" ] && out="$out $ip_address($ip_object)"
				done
			done
		done
	done
	echo $out
}
get_vxlan_interface_obj() {
	local vxlan=$1
	local out interfaces used_interface interface_alias
	cmclient -v interfaces GETO $vxlan.Interface
	for interface in $interfaces; do
		cmclient -v used_interface GETO Device.X_ADB_SDN.Service.[VXLAN=$interface]
		if [ -z "$used_interface" ]; then
			cmclient -v interface_alias GETV $interface.Alias
			out="$out $interface_alias($interface)"
		fi
	done
	echo $out
}
listRadioChannelBandFrequencies() {
	local obj=$1 max_channel_bandwidth_2_4_ghz=40 max_channel_bandwidth_5_ghz=160 \
		channel_bandwidth_802_11_ac=80 strEnum="enum:" unit="MHz" out= \
		operatingBandwidths operatingFrequencyBand val autoChannelEnable \
		e0_rev_938_regulatory_domain operating_standards band
	cmclient -v autoChannelEnable GETV ${obj}.AutoChannelEnable
	if [ "$autoChannelEnable" = "true" ]; then
		echo $out
		return
	fi
	cmclient -v operatingFrequencyBand GETV ${obj}.OperatingFrequencyBand
	cmclient -v operatingBandwidths GETMDT ${obj}.OperatingChannelBandwidth
	for operatingBandwidths in $operatingBandwidths; do
		val="${operatingBandwidths#$strEnum}"
		if [ "$val" != "$operatingBandwidths" ]; then
			band="${val%$unit}"
			if [ "$band" = "Auto" ]; then
				out="$out $val"
			elif [ "$operatingFrequencyBand" = "2.4GHz" ]; then
				[ "$band" -le "$max_channel_bandwidth_2_4_ghz" ] && out="$out $val"
			elif [ "$operatingFrequencyBand" = "5GHz" ]; then
				cmclient -v e0_rev_938_regulatory_domain GETV ${obj}.X_ADB_UseE0Rev938RegulatoryDomain
				[ "$e0_rev_938_regulatory_domain" = "false" -a "$band" -eq "$max_channel_bandwidth_5_ghz" ] && continue
				cmclient -v operating_standards GETV ${obj}.OperatingStandards
				case "$operating_standards" in
				*ac*)
					[ "$band" -le "$max_channel_bandwidth_5_ghz" ] && out="$out $val"
					;;
				*)
					[ "$band" -lt "$channel_bandwidth_802_11_ac" ] && out="$out $val"
					;;
				esac
			fi
		fi
	done
	echo $out
}
get_installed_software_modules() {
	local software_modules_obj="Device.SoftwareModules.DeploymentUnit" out
	cmclient -v out GETV "$software_modules_obj.Name"
	echo "$out"
}
load_completions
fun="$1"
shift
for a in $@; do
	fun="$fun \"$a\""
done
eval "$fun"
exit 0
