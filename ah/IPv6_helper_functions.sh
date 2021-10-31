#!/bin/sh
command -v help_ipv6_reconf_iface >/dev/null && return 0
command -v help_str_replace >/dev/null || . /etc/ah/helper_functions.sh
command -v help_lowlayer_ifname_get >/dev/null || . /etc/ah/helper_ifname.sh
INFINITE="9999-12-31T23:59:59Z"
INDEFINITE="0001-01-01T00:00:00Z"
EXP_ADDR_LENGTH=39
ipv6_hex_to_bin() {
	local hexval="$1"                    #strig to convert
	local LIMIT="${2:-$EXP_ADDR_LENGTH}" #number char to convert - using default value if no 2-nd arg is empty
	local bin=""
	i=0
	while [ "$i" -lt "$LIMIT" ]; do
		c=${hexval:$i:1}
		case $c in
		"0") bin=$bin\0000 ;;
		"1") bin=$bin\0001 ;;
		"2") bin=$bin\0010 ;;
		"3") bin=$bin\0011 ;;
		"4") bin=$bin\0100 ;;
		"5") bin=$bin\0101 ;;
		"6") bin=$bin\0110 ;;
		"7") bin=$bin\0111 ;;
		"8") bin=$bin\1000 ;;
		"9") bin=$bin\1001 ;;
		"a") bin=$bin\1010 ;;
		"A") bin=$bin\1010 ;;
		"b") bin=$bin\1011 ;;
		"B") bin=$bin\1011 ;;
		"c") bin=$bin\1100 ;;
		"C") bin=$bin\1100 ;;
		"d") bin=$bin\1101 ;;
		"D") bin=$bin\1101 ;;
		"e") bin=$bin\1110 ;;
		"E") bin=$bin\1110 ;;
		"f") bin=$bin\1111 ;;
		"F") bin=$bin\1111 ;;
		esac
		i=$((i + 1))
	done
	echo $bin
}
ipv6_bin_to_hex() {
	local binval="$1"     #strig to convert
	local LIMIT="${2:-0}" #number of binary digit to convert
	local i=0
	local hex=""
	while [ "$i" -lt "$LIMIT" ]; do
		nibble=${binval:$i:4}
		case $nibble in
		"0000") hex=$hex\0 ;;
		"0001") hex=$hex\1 ;;
		"0010") hex=$hex\2 ;;
		"0011") hex=$hex\3 ;;
		"0100") hex=$hex\4 ;;
		"0101") hex=$hex\5 ;;
		"0110") hex=$hex\6 ;;
		"0111") hex=$hex\7 ;;
		"1000") hex=$hex\8 ;;
		"1001") hex=$hex\9 ;;
		"1010") hex=$hex\a ;;
		"1011") hex=$hex\b ;;
		"1100") hex=$hex\c ;;
		"1101") hex=$hex\d ;;
		"1110") hex=$hex\e ;;
		"1111") hex=$hex\f ;;
		esac
		i=$((i + 4))
	done
	echo $hex
}
ipv6_from_ipv4_mask_to_prefix_part() {
	local add="$1"
	local len="$2"
	add=$(echo $add | sed "s/\./ /g")
	hexadd=$(printf ""%02x%02x%02x%02x"" $add)
	discharge=$((32 - len))
	bit=$(ipv6_hex_to_bin $hexadd 8)
	bit=${bit:$discharge:$len}
	ret=$(ipv6_bin_to_hex $bit $len)
	queue="00000000"
	ret=$ret$queue
	ret=${ret:0:8}
	ret=$(echo $ret | sed "s/..../&:/g")
	ret=$(echo $ret | sed "s/:$//")
	echo "$ret"
}
ipv6_find_6to4_prefix() {
	set -f
	[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
	IFS="."
	set -- $1
	[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
	set +f
	printf "2002:%02x%02x:%02x%02x" $1 $2 $3 $4
}
ipv6_from_mac_to_id() {
	local mac=$(cat /sys/class/net/"$1"/address)
	set -f
	[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
	IFS=":"
	set -- $mac
	[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
	set +f
	printf "%x%s" "$((0x$1 + 0x02))" "$2:$3ff:fe$4:$5$6"
}
prefix_from_addr_len() {
	local addr=$(ipv6_hex_to_bin "$(help_ipv6_expand $1)")
	local len=$2
	local prefix="$(expr substr $addr 1 $len)"
	local index=$((128 - $len))
	while [ $index -gt 0 ]; do
		prefix="$prefix"0
		index=$(($index - 1))
	done
	echo "$(ipv6_short_format $(help_split_chars_with_sep 4 : $(ipv6_bin_to_hex $prefix 128)))/$len"
}
help_ipv6_now() {
	date -u +"%Y-%m-%dT%H:%M:%SZ"
}
help_ipv6_lft_since_uptime() {
	[ "$1" != "_secs" ] && local _secs
	[ "$1" != "synch_status" ] && local synch_status
	[ "$1" != "lifetime" ] && local lifetime
	[ "$1" != "curr_time" ] && local curr_time
	_secs="$2"
	if [ $_secs -eq -1 ]; then
		lifetime="$INFINITE"
	else
		cmclient -v synch_status GETV Device.Time.Status
		if [ "$synch_status" != "Synchronized" ]; then
			lifetime="$INDEFINITE"
		else
			curr_time=$(date -u +"%s")
			_secs=$((_secs + curr_time))
			lifetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ" -d @"$_secs")
		fi
	fi
	eval $1='$lifetime'
}
help_ipv6_lft_from_secs() {
	local lft_secs="$1" lifetime="" curr_sec="$2"
	tmp=$((curr_sec + lft_secs))
	if [ $tmp -ge 2147483648 ]; then
		lifetime=$INFINITE
	else
		lifetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ" -d @"$tmp")
	fi
	echo "$lifetime"
}
help_ipv6_lft_to_secs() {
	local lifetime="$1" lft_secs="" curr_sec="$2" tmp
	tmp="${lifetime%T*} ${lifetime#*T}"
	tmp=${tmp%Z}
	lifetime=$(date -u +"%s" --date="$tmp")
	lft_secs=$((lifetime - curr_sec))
	echo "$lft_secs"
}
islifetimeinfinity() {
	[ "$1" = "$INFINITE" ]
}
islifetimedefined() {
	[ "$1" != "$INDEFINITE" ]
}
get_status_from_lifetime() {
	local preferredLifetime="$1" status validLifetime="$2" elem="$3" curr_time
	case "$preferredLifetime" in
	"$INFINITE")
		case "$validLifetime" in
		"$INFINITE")
			status="Preferred"
			;;
		"$INDEFINITE")
			status="Invalid"
			;;
		*)
			status="Invalid"
			;;
		esac
		;;
	"$INDEFINITE")
		status="Invalid"
		;;
	*)
		curr_time=$(date -u +"%s")
		preferredLifetime=$(help_ipv6_lft_to_secs $preferredLifetime $curr_time)
		[ $preferredLifetime -lt 0 ] && preferredLifetime=0
		case "$validLifetime" in
		"$INFINITE")
			if [ "$preferredLifetime" -gt "0" ]; then
				if [ -n "$elem" ]; then
					help_ipv6_action_timer "ADD" "$elem.PrefixStatus" "$preferredLifetime" "Deprecated"
				fi
				status="Preferred"
			else
				status="Deprecated"
			fi
			;;
		"$INDEFINITE")
			status="Invalid"
			;;
		*)
			validLifetime=$(help_ipv6_lft_to_secs $validLifetime $curr_time)
			if [ "$validLifetime" -lt "$preferredLifetime" ]; then
				status="Invalid"
			else
				if [ "$preferredLifetime" -gt "0" ]; then
					if [ -n "$elem" ]; then
						help_ipv6_action_timer "ADD" "$elem.PrefixStatus" "$preferredLifetime" "Deprecated"
						help_ipv6_action_timer "ADD" "$elem.PrefixStatus" "$validLifetime" "Invalid"
					fi
					status="Preferred"
				else
					if [ "$validLifetime" -gt "0" ]; then
						if [ -n "$elem" ]; then
							help_ipv6_action_timer "ADD" "$elem.PrefixStatus" "$validLifetime" "Invalid"
						fi
						status="Deprecated"
					else
						status="Invalid"
					fi
				fi
			fi
			;;
		esac
		;;
	esac
	echo "$status"
}
help_ipv6_get_status_from_kernel() {
	[ "$1" != 'l' ] && local l
	[ "$1" != 'v' ] && local v
	[ "$1" != 'p' ] && local p
	while read -r l v _ p _; do
		[ "$l" = 'valid_lft' ] && break
	done <<-EOF
		$(ip -6 addr show dev $2 to $3)
	EOF
	if [ -z "$v" -o -z "$p" -o "$v" = '0' ]; then
		l='Invalid'
	elif [ "$p" = '0' ]; then
		l='Deprecated'
	elif [ "$p" = 'forever' ]; then
		l='Infinite'
	else
		l='Preferred'
	fi
	eval $1='$l'
}
radvd_need_reconf() {
	local prefix="$1"
	local ipif="$2"
	local prefix_type="$3"
	local static_type="$4"
	local op="$5"
	if [ "$prefix_type" = "Static" -a "$static_type" != "PrefixDelegation" -a "$static_type" != "Child" ]; then
		for radvd_intf in $(cmclient GETO "Device.RouterAdvertisement.[Enable=true].InterfaceSetting.*.[Enable=true].[Interface=$ipif].[ManualPrefixes>$prefix]"); do
			if [ "$op" = "DEL" ]; then
				manprefixes=""
				set -f
				IFS=","
				set -- $(cmclient GETV $radvd_intf.ManualPrefixes)
				unset IFS
				set +f
				for arg; do
					[ "$arg" != "$prefix" ] && manprefixes="${manprefixes:+$manprefixes,}$arg"
				done
				cmclient -v _ SET "$radvd_intf.ManualPrefixes" "$manprefixes"
			else
				cmclient -v _ SET "Device.RouterAdvertisement.Enable true"
			fi
			break
		done
	else
		for radvd_intf in $(cmclient GETO "Device.RouterAdvertisement.[Enable=true].InterfaceSetting.*.[Enable=true].[Interface=$ipif]"); do
			if [ "$op" = "DEL" ]; then
				cmclient -u "$prefix" -v _ SET "Device.RouterAdvertisement.Enable true"
			else
				cmclient -v _ SET "Device.RouterAdvertisement.Enable true"
			fi
		done
	fi
}
help_ipv6_action_timer() {
	case "$1" in
	"ADD")
		local i eventOff actionOff setm
		cmclient -v i ADDS "Device.X_ADB_Time.Event"
		eventOff="Device.X_ADB_Time.Event.$i"
		cmclient -v i ADDS "$eventOff.Action"
		actionOff="$eventOff.Action.$i"
		setm="$actionOff.Operation=Set	$actionOff.Path=$2	$actionOff.Value=$4"
		setm="$setm	$eventOff.Alias=${2%.*}	$eventOff.DeadLine=$3	$eventOff.Type=Aperiodic	$eventOff.Enable=true"
		cmclient -v _ SETM "$setm"
		;;
	"DEL")
		local list val elem
		cmclient -v list GETO "Device.X_ADB_Time.Event.*.[Alias=${2%.*}]"
		for elem in $list; do
			cmclient -v val GETV "$elem.Action.1.Value"
			[ "${val}" = "$4" ] && cmclient -v _ DEL "$elem"
		done
		;;
	esac
}
help_ipv6_route_action_timer() {
	local actionOff eventOff i setm
	case $1 in
	"ADD")
		cmclient -v eventOff GETO "Device.X_ADB_Time.Event.*.[Alias=$2]"
		if [ -z "$eventOff" ]; then
			cmclient -v i ADDS "Device.X_ADB_Time.Event."
			eventOff="Device.X_ADB_Time.Event.$i"
			cmclient -v i ADDS "$eventOff.Action"
			actionOff="$eventOff.Action.$i"
			setm="$actionOff.Operation=Delete	$actionOff.Path=$2	$eventOff.Enable=true	$eventOff.Alias=$2	$eventOff.DeadLine=$3	$eventOff.Type=Aperiodic"
		else
			setm="$eventOff.DeadLine=$3	$eventOff.Enable=true"
		fi
		cmclient -v _ SETM "$setm"
		;;
	"DEL")
		cmclient -v _ DEL "Device.X_ADB_Time.Event.*.[Alias=$2]"
		;;
	esac
}
help_ipv6_add_prefix() {
	local _prefix="$1" _origin="$2" _onlink="$3" _autonomous="$4" _preflt="$5" _validlt="$6" ipif_prefix="$7" ipif="$8" user="$9" setm_params="" curr_sec
	if [ -z "$ipif_prefix" ]; then
		[ "$_origin" != "Static" ] && cmclient -v idxipv6pfix ADDS $ipif.IPv6Prefix || cmclient -v idxipv6pfix ADD $ipif.IPv6Prefix
		ipif_prefix="$ipif.IPv6Prefix.$idxipv6pfix"
	else
		cmclient -v enable_val GETV "$ipif_prefix.Enable"
	fi
	setm_params="$ipif_prefix.Prefix=$_prefix"
	[ -n "$_origin" ] && setm_params="$setm_params	$ipif_prefix.Origin=$_origin"
	setm_params="$setm_params	$ipif_prefix.OnLink=$_onlink"
	setm_params="$setm_params	$ipif_prefix.Autonomous=$_autonomous"
	curr_sec=$(date -u +"%s")
	case "$_preflt" in
	"-1")
		_preflt="$INFINITE"
		;;
	"0")
		IFS=. read uptime _ </proc/uptime
		setm_params="$setm_params	$ipif_prefix.X_ADB_Preferred=$uptime"
		_preflt=$(help_ipv6_now)
		;;
	*)
		IFS=. read uptime _ </proc/uptime
		uptime=$((uptime + $_preflt))
		setm_params="$setm_params	$ipif_prefix.X_ADB_Preferred=$uptime"
		_preflt=$(help_ipv6_lft_from_secs "$_preflt" "$curr_sec")
		;;
	esac
	setm_params="$setm_params	$ipif_prefix.PreferredLifetime=$_preflt"
	case "$_validlt" in
	"-1")
		_validlt="$INFINITE"
		;;
	"0")
		IFS=. read uptime _ </proc/uptime
		setm_params="$setm_params	$ipif_prefix.X_ADB_Valid=$uptime"
		_validlt=$(help_ipv6_now)
		;;
	*)
		IFS=. read uptime _ </proc/uptime
		uptime=$((uptime + $_validlt))
		setm_params="$setm_params	$ipif_prefix.X_ADB_Valid=$uptime"
		_validlt=$(help_ipv6_lft_from_secs "$_validlt" "$curr_sec")
		;;
	esac
	setm_params="$setm_params	$ipif_prefix.ValidLifetime=$_validlt"
	if [ "$_origin" != "Static" ]; then
		setm_params="$setm_params	$ipif_prefix.StaticType=Inapplicable"
	fi
	if [ -n "$enable_val" ]; then
		setm_params="$setm_params	$ipif_prefix.Enable=$enable_val"
	else
		setm_params="$setm_params	$ipif_prefix.Enable=true"
	fi
	if [ -n "$user" ]; then
		setm_params="$setm_params	$ipif_prefix.Status=Enabled"
		cmclient -u "$user" -v _ SETM "$setm_params"
	else
		cmclient -v _ SETM "$setm_params"
	fi
	echo "$ipif_prefix"
}
help_ipv6_add_address() {
	local _addr="$1" _prefix="$2" _origin="$3" _anycast="$4" _preflt="$5" _validlt="$6" ipv6_addr="$7" ipif="$8" user="$9" setm_params="" curr_sec
	if [ -z "$ipv6_addr" ]; then
		[ "$_origin" != "Static" ] && cmclient -v idxipv6 ADDS $ipif.IPv6Address || cmclient -v idxipv6 ADD $ipif.IPv6Address
		ipv6_addr="$ipif.IPv6Address.$idxipv6"
	else
		cmclient -v enable_val GETV "$ipv6_addr.Enable"
	fi
	setm_params="$ipv6_addr.IPAddress=$_addr"
	setm_params="$setm_params	$ipv6_addr.Prefix=$_prefix"
	[ -n "$_origin" ] && setm_params="$setm_params	$ipv6_addr.Origin=$_origin"
	setm_params="$setm_params	$ipv6_addr.Anycast=$_anycast"
	curr_sec=$(date -u +"%s")
	case "$_preflt" in
	"-1")
		_preflt="$INFINITE"
		;;
	"0")
		_preflt=$(help_ipv6_now)
		;;
	*)
		_preflt=$(help_ipv6_lft_from_secs "$_preflt" "$curr_sec")
		;;
	esac
	setm_params="$setm_params	$ipv6_addr.PreferredLifetime=$_preflt"
	case "$_validlt" in
	"-1")
		_validlt="$INFINITE"
		;;
	"0")
		_validlt=$(help_ipv6_now)
		;;
	*)
		_validlt=$(help_ipv6_lft_from_secs "$_validlt" "$curr_sec")
		;;
	esac
	setm_params="$setm_params	$ipv6_addr.ValidLifetime=$_validlt"
	if [ ${#7} -eq 0 ]; then
		get_status_from_lifetime "$_preflt" "$_validlt" "" >/dev/null
		setm_params="$setm_params	$ipv6_addr.IPAddressStatus=Invalid"
	fi
	if [ -n "$enable_val" ]; then
		setm_params="$setm_params	$ipv6_addr.Enable=$enable_val"
	else
		setm_params="$setm_params	$ipv6_addr.Enable=true"
	fi
	if [ -n "$user" ]; then
		setm_params="$setm_params	$ipv6_addr.Status=Enabled"
		cmclient -u "$user" -v _ SETM "$setm_params"
	else
		cmclient -v _ SETM "$setm_params"
	fi
	echo "$ipv6_addr"
}
help_split_chars_with_sep() {
	local num=$1
	local sep=$2
	local str=$3
	local i=0
	local div=$(((${#str} + ${#str} % $num) / $num))
	local q=""
	while [ $i -lt $num ]; do
		q="$q?"
		i=$((i + 1))
	done
	i=0
	while [ $i -lt $div ]; do
		tail=${str#$q}
		printf "%s" "${str%$tail}"
		if [ -n "${str%$tail}" -a -n "$tail" ]; then
			printf "%s" "$sep"
		fi
		str=$tail
		i=$((i + 1))
	done
	[ -n "$str" ] && printf "%s" "$str"
}
help_ipv6_expand() {
	local i
	local octet
	local sep=${2-:}
	set -f
	[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
	IFS=":"
	set -- $1
	[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
	set +f
	[ "${1+x}" = "x" ] || return
	printf "%.4x" "0x${1:-0}"
	shift
	for octet; do
		if [ -z "$octet" ]; then
			i=$#
			while [ $i -lt 8 ]; do
				printf "%s%.4x" "$sep" "0x0"
				i=$((i + 1))
			done
		else
			printf "%s%.4x" "$sep" "0x$octet"
		fi
	done
}
ipv6_short_format() {
	local ipv6=$1
	local i=0 group=0 group_count=0 old_group_count=0 octet prev=1 sep
	case "$ipv6" in
	*::*)
		ipv6=$(help_ipv6_expand "$ipv6")
		;;
	esac
	set -f
	[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
	IFS=":"
	set -- $ipv6
	[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
	set +f
	[ $# -eq 0 ] && return
	for octet; do
		octet=$((0x$octet))
		if [ $octet -eq 0 ]; then
			group_count=$((group_count + 1))
			[ $group_count -gt $old_group_count ] && group=$i
			[ $prev -ne 0 ] && i=$((i + 1))
		else
			old_group_count=$group_count
			group_count=0
		fi
		prev=$octet
	done
	i=0 prev=1
	for octet; do
		octet=$((0x$octet))
		[ $octet -eq 0 -a $prev -ne 0 ] && i=$((i + 1))
		if [ $octet -ne 0 -o $group -ne $i ]; then
			if [ $prev -eq 0 -a $group -eq $i ]; then
				printf "%s" "::"
				unset sep
			fi
			printf "%s%x" "$sep" "$octet"
			: ${sep=:}
		fi
		prev=$octet
	done
	[ $octet -eq 0 -a $group -eq $i ] && printf "::"
}
help_ipv6_extract_mac() {
	local ipv6=$(help_ipv6_expand "$1" "")
	set -- $(help_split_chars_with_sep 2 " " "${ipv6#fe80000000000000}")
	printf "%.2x:%s" "$((0x$1 - 0x02))" "$2:$3:$6:$7:$8"
}
_ipv6_proc_enable_one() {
	local newStatus="$1"
	local ifname="$2"
	local obj allList ifaceList="" iface addr error="" erraddr \
		slaacenable="true" newAutoconf="1"
	[ -n "$ifname" -a -d "/sys/class/net/$ifname" -o "$ifname" = "default" -o "$ifname" = "all" ] || return
	obj=$(help_obj_from_ifname_get "$ifname")
	help_ip_interface_get allList "$obj"
	for obj in $allList; do
		help_lowlayer_ifname_get iface "$obj"
		[ "$ifname" = "$iface" ] && ifaceList="${ifaceList} ${obj}"
	done
	for iface in $ifaceList; do
		cmclient -v erraddr GETO "${iface}.IPv6Address.[Status=Error]"
		[ ${#erraddr} -ne 0 ] && error="1"
		if [ "$newStatus" = "false" ]; then
			for addr in $erraddr; do
				cmclient -v _ SET "${addr}.Status" Disabled
			done
		fi
	done
	if [ ${#error} -eq 0 ]; then
		if [ "$newStatus" = "true" ]; then
			for iface in $ifaceList; do
				cmclient -v slaacenable GETV "${iface}.X_ADB_SLAACEnable"
				[ "$slaacenable" = "false" ] && newAutoconf="0" && break
			done
			echo "$newAutoconf" >/proc/sys/net/ipv6/conf/$ifname/autoconf
			echo 0 >/proc/sys/net/ipv6/conf/$ifname/disable_ipv6
			echo 1 >/proc/sys/net/ipv6/conf/$ifname/forwarding
			echo 64 >/proc/sys/net/ipv6/conf/$ifname/accept_ra_rt_info_max_plen
		else
			echo 1 >/proc/sys/net/ipv6/conf/$ifname/disable_ipv6
			echo 0 >/proc/sys/net/ipv6/conf/$ifname/forwarding
			echo 0 >/proc/sys/net/ipv6/conf/$ifname/accept_ra_rt_info_max_plen
		fi
	fi
}
ipv6_proc_enable() {
	local newStatus="$1"
	local ifname="$2"
	if [ "$ifname" = "all" ]; then
		if [ "$newStatus" = "true" ]; then
			cmclient -v itf_list GETO Device.IP.Interface.[IPv6Enable=true]
			echo 1 >/proc/sys/net/ipv6/conf/$ifname/forwarding
		else
			cmclient -v itf_list GETO Device.IP.Interface
			echo 0 >/proc/sys/net/ipv6/conf/$ifname/forwarding
		fi
		for itf in $itf_list; do
			help_lowlayer_ifname_get ifname $itf
			[ -z "$ifname" ] && continue
			_ipv6_proc_enable_one "$newStatus" "$ifname"
		done
	else
		_ipv6_proc_enable_one "$newStatus" "$ifname"
	fi
}
ipv6_neigh_proc_enable() {
	local newStatus="$1"
	local ifname="$2"
	local entry=
	local entries=
	local itf_list=
	case "$ifname" in
	"all")
		entries="/proc/sys/net/ipv6/conf/*"
		case "$newStatus" in
		"true")
			cmclient -v disabled_itf_list GETO "Device.NeighborDiscovery.InterfaceSetting.[Enable=false]"
			for entry in $disabled_itf_list; do
				cmclient -v itf GETV "$entry.Interface"
				help_lowlayer_ifname_get itf "$itf"
				if [ -z "$itf_list" ]; then
					itf_list="$itf"
				else
					itf_list="$itf_list $itf"
				fi
			done
			for entry in $entries; do
				itf=${entry##*/}
				found=""
				for disabled in $itf_list; do
					if [ "$itf" = "$disabled" ]; then
						found="1"
					fi
				done
				if [ -z "$found" ]; then
					echo 3 >"$entry/router_solicitations"
					echo 1 >"$entry/dad_transmits"
				fi
			done
			;;
		"false")
			for entry in $entries; do
				echo 0 >"$entry/router_solicitations"
				echo 0 >"$entry/dad_transmits"
			done
			;;
		esac
		;;
	*)
		{ [ -n "$ifname" ] && [ -d /sys/class/net/"$ifname" ]; } || return
		case "$newStatus" in
		"true")
			echo 3 >/proc/sys/net/ipv6/conf/$ifname/router_solicitations
			echo 1 >/proc/sys/net/ipv6/conf/$ifname/dad_transmits
			;;
		"false")
			echo 0 >/proc/sys/net/ipv6/conf/$ifname/router_solicitations
			echo 0 >/proc/sys/net/ipv6/conf/$ifname/dad_transmits
			;;
		esac
		;;
	esac
}
help_ipv6_reconf_iface() {
	local ifname="$1"
	local itf_list itf entry status
	cmclient -v status GETV Device.IP.IPv6Enable
	if [ "$status" = "false" ]; then
		ipv6_proc_enable "false" "$ifname"
		return
	fi
	cmclient -v itf_list GETO Device.IP.Interface
	status="false"
	for entry in $itf_list; do
		help_lowlayer_ifname_get itf "$entry"
		[ "$itf" != "$ifname" ] && continue
		cmclient -v status GETV $entry.IPv6Enable
		break
	done
	ipv6_proc_enable "$status" "$ifname"
	cmclient -v status GETV Device.NeighborDiscovery.Enable
	if [ "$status" = "false" ]; then
		ipv6_neigh_proc_enable "false" "$ifname"
		return
	fi
	cmclient -v itf_list GETV Device.NeighborDiscovery.InterfaceSetting.Interface
	for entry in $itf_list; do
		help_lowlayer_ifname_get itf "$entry"
		[ "$itf" != "$ifname" ] && continue
		cmclient -v status GETV $entry.Enable
		cmclient -v _ SET $entry.Enable "$status"
		return
	done
	ipv6_neigh_proc_enable "false" "$ifname"
}
help_is_dhcpv6_client_stateful() {
	local request_address request_prefix dhcpv6_clisent_path="$1"
	cmclient -v request_address GETV "$dhcpv6_clisent_path.RequestAddresses"
	cmclient -v request_prefix GETV "$dhcpv6_clisent_path.RequestPrefixes"
	[ "$request_address" = "true" -o "$request_prefix" = "true" ]
}
help_dhcpv6_client_clean_stateless_options() {
	[ "$1" != "each_option" ] && local each_option
	[ "$1" != "__options_list" ] && local __options_list="$2" || __options_list="$2"
	for each_option in 242 243; do
		__options_list=$(help_item_replace_uniq_in_list "$__options_list" "$each_option" "")
	done
	eval $1='$__options_list'
}
help_create_child_prefix() {
	local parent_addr=$1
	local parent_length=$2
	local child_unique=$3
	local child_bits_total=$4
	local child_length=$(($parent_length + $child_bits_total))
	[ $child_length -gt 128 ] && return 1
	if [ $child_bits_total -eq 0 ]; then
		echo "$parent_addr/$parent_length"
		return 1
	fi
	parent_addr=$(ipv6_hex_to_bin $(help_ipv6_expand $parent_addr))
	local unique_child_hex=$(printf %x $child_unique)
	local unique_child_bin=$(ipv6_hex_to_bin $unique_child_hex ${#unique_child_hex})
	unique_child_bin=${unique_child_bin#*1}
	[ "$unique_child_bin" = "0000" ] && unique_child_bin="0" || unique_child_bin="1"$unique_child_bin
	local unique_child_bin_length=${#unique_child_bin}
	[ $unique_child_bin_length -gt $child_bits_total ] && return 1
	local index=$unique_child_bin_length
	local reverse_unique_child_bin
	while [ $index -ne 0 ]; do
		reverse_unique_child_bin=$reverse_unique_child_bin$(expr substr $unique_child_bin $index 1)
		index=$(($index - 1))
	done
	local child_adr=$(expr substr $parent_addr 1 $parent_length)$reverse_unique_child_bin
	index=$((128 - $unique_child_bin_length - $parent_length))
	while [ $index -gt 0 ]; do
		child_adr="$child_adr"0
		index=$(($index - 1))
	done
	echo "$(ipv6_short_format $(help_split_chars_with_sep 4 : $(ipv6_bin_to_hex $child_adr 128)))/$child_length"
}
help_ipv6_forwarding_static_refresh() {
	local itf="$1"
	[ ${#itf} -ne 0 ] && cmclient SET "Device.Routing.Router.*.IPv6Forwarding.*.[Interface=$itf].[Origin=Static].[Enable=true].[Status!Enabled].Enable" "true"
	cmclient SET "Device.Routing.Router.*.IPv6Forwarding.*.[Interface=].[Origin=Static].[Enable=true].[Status!Enabled].Enable" "true"
}
