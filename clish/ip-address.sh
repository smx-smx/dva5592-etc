#!/bin/sh
. /etc/clish/clish-commons.sh
. /etc/ah/IPv6_helper_functions.sh 2>/dev/null
is_interface_valid() {
	local i
	local base_iface="$1"
	local ip_ifaces="$(upper_interfaces_get $base_iface Device.IP.Interface)"
	for i in $ip_ifaces; do
		if [ "$base_iface" = "$(ip_interface_get_cli_ll $i)" ]; then
			echo "$i"
			return
		fi
	done
}
ip6_test_prefix() {
	local this="$1"
	local that="$2"
	local test
	cmclient -v test GETO "$this.IPv6Prefix.[Prefix=$that]"
	[ -n "$test" ] && echo "WARNING: prefix \"$that\" already exists" && exit 0
}
ip_prefix_delete() {
	local this="$(ll_obj_to_ip_obj_ex $1)"
	local prefix_obj="$2"
	local list entry
	cmclient -v list GETO "$this.IPv6Address.[Prefix=$prefix_obj]"
	for entry in $list $prefix_obj; do
		ip_address_static_remove "$entry"
	done
}
ip_prefix_add() {
	local this="$(ll_obj_to_ip_obj_ex $1)"
	local prefix_len="${2#*/}"
	local addr="${2%/*}"
	local alias_name="${3}"
	local ipv6prefixObj
	local prefix
	if [ -n "$prefix_len" ]; then
		prefix=$(prefix_from_addr_len $(help_ipv6_expand "$addr") "$prefix_len")
		[ -n "$prefix" ] && ip6_test_prefix "$this" "$prefix"
	fi
	if [ -n "$alias_name" ]; then
		cmclient -v idx ADD "$this.IPv6Prefix.[Alias=$alias_name]"
		ipv6prefixObj=$this.IPv6Prefix.$idx
	fi
	help_ipv6_add_prefix "$prefix" "Static" false false "-1" "-1" "$ipv6prefixObj" "$this" "$alias_name" >/dev/null
}
ipv4_get_obj_address_from_alias_or_addr() {
	local ip_addr_tab="$1"
	local prefix="${2#*/}"
	local address="${2%/*}"
	local obj
	if [ "$address" != "$prefix" ]; then
		local subnet="$(ipv4_prefix2mask $prefix)"
		cmclient -v obj GETO "${ip_addr_tab}.[IPAddress=$address].[SubnetMask=$subnet]"
	else
		[ -n "$2" ] && cmclient -v obj GETO "${ip_addr_tab}.[Alias=$2]"
	fi
	for o in $obj; do
		echo -n "$o"
		return
	done
}
ipv6_get_obj_address_from_alias_or_addrprfxlen() {
	local ip_obj="$1"
	local prefix_len="${2#*/}"
	local address="${2%/*}"
	local obj
	if [ "$address" != "$prefix_len" ]; then
		local prefix=$(prefix_from_addr_len "$address" "$prefix_len")
		local ipv6_objs ipv6_obj test
		cmclient -v ipv6_objs GETO "${ip_obj}.[IPAddress=$address]"
		for ipv6_obj in $ipv6_objs; do
			cmclient -v test GETO "%($ipv6_obj.Prefix).[Prefix=$prefix]"
			[ -n "$test" ] && obj="$ipv6_obj" && break
		done
	else
		[ -n "$2" ] && cmclient -v obj GETO "${ip_obj}.[Alias=$2]"
	fi
	echo -n "$obj"
}
ipv6_address_set_addr() {
	local obj
	local prefix_len="${3#*/}"
	local address="${3%/*}"
	local setm
	cmclient -v ip_obj GETO "$1"
	cmclient -v obj GETO "$2"
	if [ "$address" != "$prefix_len" ]; then
		local prefix=$(prefix_from_addr_len "$address" "$prefix_len")
		local prefix_obj
		cmclient -v prefix_obj GETO "$ip_obj.IPv6Prefix.[Origin=Static].[Prefix=$prefix]"
		if [ -z "$prefix_obj" ]; then
			ip6_test_prefix "$ip_obj" "$prefix"
			prefix_obj=$(help_ipv6_add_prefix "$prefix" "Static" false false "-1" "-1" "" "$ip_obj")
		fi
		setm="${setm:+$setm	}$obj.IPAddress=$address"
		setm="${setm:+$setm	}$obj.Prefix=$prefix_obj"
	fi
	[ -n "$setm" ] && cmclient SETM "$setm" >/dev/null
}
ipv6_address_add() {
	local ip_obj
	local obj
	local prefix_len="${2#*/}"
	local address="${2%/*}"
	local address_short="$(ipv6_short_format $address)"
	local alias_name="$3"
	if [ "$address" != "$prefix_len" ]; then
		cmclient -v ip_obj GETO "$1"
		cmclient -v ipv6_match GETO "${ip_obj%.*}.IPv6Address.[Origin=Static].[IPAddress=$address_short]"
		if [ -n "$ipv6_match" ]; then
			local prefixlen_matched
			cmclient -v prefix_matched GETV "%($ipv6_match.Prefix).Prefix"
			prefixlen_matched="${prefix_matched#*/}"
			die "ERROR: The specified IPv6 address already exists. [ Address: $address_short/$prefix_len - Current Address: $address_short/$prefixlen_matched ]"
		fi
		local prefix=$(prefix_from_addr_len "$address" "$prefix_len")
		local prefix_obj
		cmclient -v prefix_obj GETO "$ip_obj.IPv6Prefix.[Origin=Static].[Prefix=$prefix]"
		if [ -z "$prefix_obj" ]; then
			ip6_test_prefix "$ip_obj" "$prefix"
			prefix_obj=$(help_ipv6_add_prefix "$prefix" "Static" false false "-1" "-1" "" "$ip_obj")
		fi
		if [ -z "${alias_name}" ]; then
			cmclient -v idx ADD "$ip_obj.IPv6Address.[Origin=Static].[IPAddress=$address].[Prefix=$prefix_obj]" >/dev/null
		else
			obj="$ip_obj.IPv6Address"
			cmclient -v idx ADD "$ip_obj.IPv6Address.[Alias=${alias_name}]" >/dev/null
			cmclient -v res SETM "$obj.Origin=Static	$obj.IPAddress=$address	$obj.Prefix=$prefix_obj"
		fi
	fi
}
ipv4_address_add() {
	local obj
	local ip_iface="$1"
	local prefix address subnet
	local alias_name="${3}"
	local setm
	if [ -n "$2" ]; then
		prefix="${2#*/}"
		address="${2%/*}"
		subnet="$(ipv4_prefix2mask $prefix)"
	fi
	if [ -z "${alias_name}" ]; then
		cmclient -v idx ADD "$ip_iface.IPv4Address.[IPAddress=$address].[SubnetMask=$subnet]" >/dev/null
		obj="$ip_iface.IPv4Address.$idx"
		setm=${setm:+$setm	}$obj.AddressingType=Static
	else
		cmclient -v idx ADD "$ip_iface.IPv4Address.[Alias=${alias_name}]" >/dev/null
		obj="$ip_iface.IPv4Address.$idx"
		setm="${setm:+$setm	}$obj.IPAddress=$address	$obj.SubnetMask=$subnet"
		setm="${setm:+$setm	}$obj.AddressingType=Static"
	fi
	cmclient SETM "$setm" >/dev/null
}
ip_address_add() {
	local ip_type="$1"
	local ip_iface="$2"
	local address="$3"
	local obj
	local idx
	local setm=""
	case "$ip_type" in
	v4)
		cmclient -v idx ADD $ip_iface.IP${ip_type}Address >/dev/null
		obj="$ip_iface.IP${ip_type}Address.$idx"
		setm=${setm:+$setm	}$obj.IPAddress=$address
		setm=${setm:+$setm	}$obj.SubnetMask="$4"
		setm=${setm:+$setm	}$obj.AddressingType=Static
		;;
	v6)
		local prefix_obj="$4"
		local prefix_len
		local prefix
		if [ "$prefix_obj" = "new" ]; then
			[ -n "$5" ] && prefix_len="$5" || die "ERROR: you must set the prefix length"
			prefix=$(prefix_from_addr_len "$address" "$prefix_len")
			address="$(ipv6_short_format $address)"
			cmclient -v prefix_obj GETO "${ip_iface}.IPv6Prefix.[Prefix=${prefix}]"
			[ ${#prefix_obj} -eq 0 ] && prefix_obj=$(help_ipv6_add_prefix "$prefix" "Static" false false "-1" "-1" "" "$ip_iface")
		else
			local temp
			cmclient -v temp GETV "$prefix_obj.Prefix"
			prefix_len="${temp##*/}"
			prefix="${temp%%/*}"
			local addr_bits=$(ipv6_hex_to_bin "$(help_ipv6_expand $address)")
			addr_bits="${addr_bits:$prefix_len:${#addr_bits}}"
			local prefix_bits=$(ipv6_hex_to_bin "$(help_ipv6_expand $prefix)")
			prefix_bits="${prefix_bits:0:$prefix_len}"
			address=$(ipv6_short_format $(help_split_chars_with_sep 4 ":" $(ipv6_bin_to_hex "${prefix_bits}${addr_bits}" 128)))
			[ "$address" = "0" -o "$prefix" = "0" ] && die "ERROR: wrong IP address or IP prefix"
			cmclient -v test GETO "$ip_iface.IPv6Address.[IPAddress=$address]"
			if [ -n "$test" ]; then
				echo "WARNING: IP address \"$that\" already exists"
				exit 0
			fi
		fi
		obj=$(help_ipv6_add_address "$address" "$prefix_obj" "" "false" "-1" "-1" "" "$ip_iface")
		;;
	esac
	setm=${setm:+$setm	}$obj.Enable=true
	cmclient SETM "$setm" >/dev/null
}
ip_interface_get_or_create() {
	local type="$1"
	local tr_iface="$2"
	local alias_name="$3"
	local val
	local err_msg
	local ip_iface=$(ll_obj_to_ip_obj_ex "$tr_iface")
	: "${upstream:=false}"
	if [ -z "$ip_iface" ]; then
		ip_iface=$(ip_interface_add "$tr_iface" "$alias_name")
	elif [ -n "$alias_name" ]; then
		cmclient -v val GETV "$ip_iface.Alias"
		if [ "$alias_name" != "$val" ]; then
			cmclient -v name GETV $tr_iface.Alias
			echo "IP \"$val\" is already associated with $name" >&2
			return 1
		fi
	fi
	echo "$ip_iface"
	return 0
}
ip_address_add_entry() {
	local type="$1"
	local cli_id="$2"
	local ip_ver="$3"
	local ip_addr="$4"
	local ip_mask="$5"
	local ip_iface
	ip_iface=$(ip_interface_get_or_create "$type" "$cli_id")
	if [ $? -ne 0 ]; then
		die "$ip_iface"
	fi
	case "$type" in
	static)
		local ip_prefix_len="$6"
		cmclient -v val GETO "$ip_iface.IPv${ip_ver}Address.[IPAddress=$ip_addr]"
		[ -z "$val" ] || die "ERROR: interface $cli_id already has IP address $ip_addr"
		ip_address_add "v${ip_ver}" "$ip_iface" "$ip_addr" "$ip_mask" "$ip_prefix_len"
		;;
	dhcp)
		local dhcp_obj
		local dhcp_path="Device.DHCPv${ip_ver}.Client"
		local setm
		cmclient -v dhcp_obj GETO "$dhcp_path.*.[Interface=$ip_iface]"
		if [ -z "$dhcp_obj" ]; then
			cmclient -v idx ADD "$dhcp_path"
			cm_err_maybe_die "$idx" "ERROR: Can't add DHCPv${ip_ver} Client for $cli_id"
			dhcp_obj="$dhcp_path.$idx"
		fi
		setm="${dhcp_obj}.Interface=$ip_iface"
		[ "$ip_ver" -eq 6 ] && setm="${ip_iface}.IPv6Enable=true	${setm}"
		cmclient -v setm_out SETM "${setm}"
		cm_err_maybe_die "$setm_out" "ERROR: enabling DHCP"
		echo "$dhcp_obj"
		;;
	esac
}
ip_address_static_remove() {
	local ip_int="${1%.IPv*}"
	local all_ips=""
	local addr=""
	local entry=""
	[ -n "$1" ] && cmclient DEL "$1" >/dev/null 2>&1
	cmclient -v all_ips GETO "${ip_int}.IPv4Address"
	[ -n "$all_ips" ] && return
	cmclient -v all_ips GETO "${ip_int}.IPv6Address"
	for entry in $all_ips; do
		cmclient -v addr GETV "${entry}.IPAddress"
		case $addr in
		"fe80:"*) continue ;; #ignoring link-local addersses
		*) return ;;
		esac
	done
}
obj_ipv4_address_set_addr() {
	local obj
	local prefix="${4#*/}"
	local address="${4%/*}"
	local exclude=${6:-"false"}
	local setm
	if [ "$address" != "$prefix" ]; then
		local subnet="$(ipv4_prefix2mask $prefix)"
		setm="${setm:+$setm	}$1.$2=$address"
		setm="${setm:+$setm	}$1.$3=$subnet"
		[ -n "$5" ] && setm="${setm:+$setm	}$1.$5=$exclude"
	fi
	[ -n "$setm" ] && cmclient SETM "$setm" >/dev/null
}
obj_ipv4_address_print_addr() {
	local exclude=""
	local addr=""
	local submask=""
	cmclient -v addr GETV "$1.$2"
	cmclient -v submask GETV "$1.$3"
	[ -n "$4" ] && cmclient -v exclude GETV "$1.$4"
	if [ -n "${addr}" -a -n "${submask}" ]; then
		prefix=$(. /etc/clish/clish-commons.sh && ipv4_mask2prefix ${submask})
		[ "$exclude" = "true" ] && echo -n "$addr/$prefix exclude" || echo -n "$addr/$prefix"
	fi
}
obj_ipv4_address_add_addr() {
	local inlist="$3"
	local prefix
	local address
	local subnet
	local list
	local addr_with_cidr
	[ "$4" = "true" ] && list="" || cmclient -v list GETV "$1.$2"
	if [ -n "$inlist" ]; then
		inlist="$inlist,"
		while [ -n "$inlist" ]; do
			addr_with_cidr=${inlist%%","*}
			prefix="${addr_with_cidr#*/}"
			address="${addr_with_cidr%/*}"
			if [ "$address" != "$prefix" ]; then
				subnet="$(ipv4_prefix2mask $prefix)"
			else
				subnet="255.255.255.255"
			fi
			list="$list"${list:+,}"$address/$subnet"
			inlist=${inlist#*","}
		done
		cmclient SET "$1.$2" "$list" >/dev/null
	fi
}
obj_ipv4_address_print_list_addr() {
	local addr
	local submask
	local addr_with_submask
	local list
	local output
	local prefix
	cmclient -v list GETV "$1.$2"
	if [ -n "$list" ]; then
		list="$list,"
		output=""
		while [ -n "$list" ]; do
			addr_with_submask=${list%%","*}
			submask="${addr_with_submask#*/}"
			addr="${addr_with_submask%/*}"
			if [ "$addr" != "$submask" ]; then
				prefix=$(. /etc/clish/clish-commons.sh && ipv4_mask2prefix ${submask})
			else
				prefix="32"
			fi
			if [ "$3" = "complete" ]; then
				output="$output${output:+
}$addr/$prefix($addr_with_submask)"
			else
				output="$output${output:+,}$addr/$prefix"
			fi
			list=${list#*","}
		done
	fi
	if [ "$3" = "true" -o "$3" = "complete" ]; then
		echo "$output"
	else
		[ -n "$output" ] && echo -n "$output"
	fi
}
ipv4_address_compare() {
	local addr1="$1"
	local addr2="$2"
	local oct1 oct2
	for i in $(seq 4); do
		oct1=${addr1%%"."*}
		oct2=${addr2%%"."*}
		[ $oct1 -lt $oct2 ] && exit 255
		[ $oct1 -gt $oct2 ] && exit 1
		addr1=${addr1#*"."}
		addr2=${addr2#*"."}
	done
	exit 0
}
case "$1" in
"ipv4_get_obj_address_from_alias_or_addr")
	ipv4_get_obj_address_from_alias_or_addr "$2" "$3"
	;;
"ipv6_get_obj_address_from_alias_or_addrprfxlen")
	ipv6_get_obj_address_from_alias_or_addrprfxlen "$2" "$3"
	;;
"ipv4_address_add")
	ipv4_address_add "$2" "$3" "$4"
	;;
"dhcp")
	ip_address_add_entry dhcp "$2" 4
	;;
"ipv6_address_set_addr")
	ipv6_address_set_addr "$2" "$3" "$4"
	;;
"ipv6_address_add")
	ipv6_address_add "$2" "$3" "$4"
	;;
"dhcpv6")
	ip_address_add_entry dhcp "$2" 6
	;;
"delete_prefix")
	ip_prefix_delete "$2" "$3"
	;;
"add_prefix")
	ip_prefix_add "$2" "$3" "$4"
	;;
"ip_interface_get_or_create")
	ip_interface_get_or_create "$2" "$3" "$4"
	;;
"obj_ipv4_address_set_addr")
	obj_ipv4_address_set_addr "$2" "$3" "$4" "$5" "$6" "$7"
	;;
"obj_ipv4_address_print_addr")
	obj_ipv4_address_print_addr "$2" "$3" "$4" "$5"
	;;
"obj_ipv4_address_add_addr")
	obj_ipv4_address_add_addr "$2" "$3" "$4" "$5"
	;;
"obj_ipv4_address_print_list_addr")
	obj_ipv4_address_print_list_addr "$2" "$3" "$4"
	;;
"ipv4_address_compare")
	ipv4_address_compare "$2" "$3"
	;;
esac
