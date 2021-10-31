#!/bin/sh
AH_NAME="RouterAdv"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/helper_ifname.sh
file="/tmp/radvd.conf"
radvd_check_defroute() {
	cmclient -v ula_prefix GETV "Device.IP.ULAPrefix"
	cmclient -v ula_subnet GETV "Device.IP.X_ADB_ULASubnet"
	if [ -n "$ula_prefix" -a -n "$ula_subnet" ]; then
		ula_pref="${ula_prefix}:${ula_subnet}::/64"
		cmclient -v other_prefix GETO "$ipif.IPv6Prefix.[Prefix!${ula_pref}].[Prefix!fe80::/64]"
	else
		cmclient -v other_prefix GETO "$ipif.IPv6Prefix.[Prefix!fe80::/64].[Prefix!]"
	fi
	[ -z "$other_prefix" ] && return 1
	cmclient -v ipv6_route GETO "Device.Routing.Router.*.IPv6Forwarding.[DestIPPrefix=].[Status=Enabled]"
	[ -n "$ipv6_route" ] && return 0
	cmclient -v ipv6_route GETO "Device.Routing.Router.*.IPv6Forwarding.[DestIPPrefix=::/0].[Status=Enabled]"
	[ -n "$ipv6_route" ] && return 0
	return 1
}
radvd_get_prefix_list() {
	local if="$1" prefix_list="" to_delete="$user" objs objs2 objs3
	cmclient -v prefix_list GETV "$if.ManualPrefixes"
	cmclient -v ipif GETV "$if.Interface"
	cmclient -v objs GETO "$ipif.IPv6Prefix.*.[Origin=AutoConfigured]"
	cmclient -v objs2 GETO "$ipif.IPv6Prefix.*.[Origin=Child]"
	for ipv6prefix in $objs $objs2 $objs3; do
		[ "$ipv6prefix" = "$to_delete" ] && continue
		if [ -z "$prefix_list" ]; then
			prefix_list="$ipv6prefix"
		else
			prefix_list="$prefix_list,$ipv6prefix"
		fi
	done
	echo "$prefix_list"
}
setup_lifetimes() {
	local preferredlifetime="$1" validlifetime="$2" mode="$3" base \
		label value
	case "$mode" in
	date)
		base=$(date -u +"%s")
		;;
	uptime)
		IFS=. read base _ </proc/uptime
		;;
	esac
	for label in AdvPreferredLifetime AdvValidLifetime; do
		case "$label" in
		AdvPreferredLifetime) value="$preferredlifetime" ;;
		AdvValidLifetime) value="$validlifetime" ;;
		esac
		case "$mode" in
		date)
			if [ "$value" = "$INFINITE" ]; then
				value='infinity'
			elif [ "$value" = "$INDEFINITE" ]; then
				value=0
			elif [ -n "$value" ]; then
				value=$(help_ipv6_lft_to_secs "$value" "$base")
			fi
			;;
		uptime)
			value=$((value - base))
			;;
		esac
		[ -z "$value" ] && value=0
		if [ "$value" != 'infinity' ] && [ $value -le 0 ]; then
			value=0
		fi
		echo "		$label $value;"
	done
}
radvd_check_preferred() {
	local prefix prefix_enable prefix_status prefix_val uptime plt vlt curr_sec plt_sec
	set -f
	IFS=","
	set -- $1
	unset IFS
	set +f
	for prefix; do
		cmclient -v prefix_enable GETV "$prefix.Enable"
		cmclient -v prefix_status GETV "$prefix.PrefixStatus"
		cmclient -v prefix_val GETV "$prefix.Prefix"
		case "$prefix_val" in
		fec0:0:0:ffff::*) prefix_enable='false' ;;
		esac
		if [ "$prefix_enable" = "true" -a "$prefix_status" != "Invalid" -a -n "$prefix_val" ]; then
			if [ "$prefix_status" = "Unknown" ]; then
				IFS=. read uptime _ </proc/uptime
				cmclient -v plt GETV "$prefix.X_ADB_Preferred"
				plt=$((plt - uptime))
				[ $plt -gt 0 ] && return 0
			else
				cmclient -v plt GETV $prefix.PreferredLifetime
				[ "$plt" = "$INDEFINITE" ] && continue
				[ "$plt" = "$INFINITE" ] && return 0
				curr_sec=$(date -u +"%s")
				plt_sec=$(help_ipv6_lft_to_secs "$plt" "$curr_sec")
				[ "$plt_sec" -gt 0 ] && return 0
			fi
		fi
	done
	return 1
}
create_intf_subentry() {
	local obj ip_list lifetime flush
	for obj in $1; do
		[ -n "$2" -a "$2" = "$obj" ] && continue
		cmclient -v ip_list GETV "$obj.Value"
		ip_list=$(help_tr "," " " "$ip_list")
		cmclient -v lifetime GETV "$obj.X_ADB_OptionLifetime"
		cmclient -v flush GETV "$obj.X_ADB_OptionFlush"
		echo "        $3 $ip_list {"
		case "$lifetime" in
		"") ;;
		"-1") echo "                $4 infinity;" ;;
		*) echo "                $4 $lifetime;" ;;
		esac
		case "$flush" in
		"true") echo "                $5 on;" ;;
		"false") echo "                $5 off;" ;;
		esac
		echo "        };"
	done
}
create_entry_for_intf() {
	local tmp objs prefix lifetime pref flush ip_list
	echo "interface $1 {"
	echo "	IgnoreIfMissing off;"
	echo "	AdvSendAdvert on;"
	cmclient -v tmp GETV $2.AdvCurHopLimit
	echo "	AdvCurHopLimit $tmp;"
	cmclient -v manprefixlist -u "$user" GETV $2.Prefixes
	if [ ${#manprefixlist} -gt 0 ] && radvd_check_preferred "$manprefixlist" && radvd_check_defroute; then
		cmclient -v tmp GETV $2.AdvDefaultLifetime
		echo "	AdvDefaultLifetime $tmp;"
	else
		echo "	AdvDefaultLifetime 0;"
	fi
	cmclient -v mtu GETV $2.AdvLinkMTU
	[ $mtu -gt 0 ] && echo "	AdvLinkMTU $mtu;"
	cmclient -v tmp GETV $2.AdvManagedFlag
	[ "$tmp" = "true" ] && echo "	AdvManagedFlag on;"
	cmclient -v tmp GETV $2.AdvMobileAgentFlag
	[ "$tmp" = "true" ] && echo "	AdvHomeAgentFlag on;"
	cmclient -v tmp GETV $2.AdvNDProxyFlag
	if [ "$tmp" = "true" ]; then
		echo 1 >/proc/sys/net/ipv6/conf/$1/proxy_ndp
	else
		echo 0 >/proc/sys/net/ipv6/conf/$1/proxy_ndp
	fi
	cmclient -v tmp GETV $2.AdvOtherConfigFlag
	[ "$tmp" = "true" ] && echo "	AdvOtherConfigFlag on;"
	cmclient -v advPrefRouterFlag GETV $2.AdvPreferredRouterFlag
	case "$advPrefRouterFlag" in
	"Low") echo "	AdvDefaultPreference low;" ;;
	"Medium") echo "	AdvDefaultPreference medium;" ;;
	"High") echo "	AdvDefaultPreference high;" ;;
	esac
	cmclient -v tmp GETV $2.AdvReachableTime
	echo "	AdvReachableTime $tmp;"
	cmclient -v tmp GETV $2.AdvRetransTimer
	echo "	AdvRetransTimer $tmp;"
	cmclient -v tmp GETV $2.MaxRtrAdvInterval
	echo "	MaxRtrAdvInterval $tmp;"
	cmclient -v tmp GETV $2.MinRtrAdvInterval
	echo "	MinRtrAdvInterval $tmp;"
	manprefixlist="$manprefixlist,"
	while [ -n "$manprefixlist" ]; do
		prefix="${manprefixlist%%,*}"
		cmclient -v prefix_enable GETV "$prefix.Enable"
		cmclient -v prefix_status GETV "$prefix.PrefixStatus"
		cmclient -v prefix_val GETV "$prefix.Prefix"
		case "$prefix_val" in
		fec0:0:0:ffff::*) prefix_val='' prefix_enable='false' ;;
		esac
		if [ "$prefix_enable" = "true" -a "$prefix_status" != "Invalid" -a -n "$prefix_val" ]; then
			cmclient -v validlifetime GETV $prefix.ValidLifetime
			cmclient -v preferredlifetime GETV $prefix.PreferredLifetime
			echo "	prefix $prefix_val {"
			cmclient -v tmp GETV $prefix.OnLink
			if [ "$tmp" = "true" ]; then
				echo "		AdvOnLink on;"
			else
				echo "		AdvOnLink off;"
			fi
			cmclient -v tmp GETV $prefix.Autonomous
			if [ "$tmp" = "true" ]; then
				echo "		AdvAutonomous on;"
			else
				echo "		AdvAutonomous off;"
			fi
			if [ "$prefix_status" = "Unknown" ]; then
				cmclient -v preferredlifetime GETV "$prefix.X_ADB_Preferred"
				cmclient -v validlifetime GETV "$prefix.X_ADB_Valid"
				setup_lifetimes "$preferredlifetime" "$validlifetime" 'uptime'
			else
				setup_lifetimes "$preferredlifetime" "$validlifetime" 'date'
			fi
			echo "	};"
		fi
		resto="${manprefixlist#*,}"
		manprefixlist="$resto"
	done
	cmclient -v objs GETO "$2.Option.*.[Enable=true].[Tag=24].[X_ADB_Type=String]"
	for route_obj in $objs; do
		[ -n "$3" -a "$3" = "$route_obj" ] && continue
		cmclient -v prefix GETV "$route_obj.Value"
		cmclient -v lifetime GETV "$route_obj.X_ADB_OptionLifetime"
		cmclient -v pref GETV "$route_obj.X_ADB_OptionPreference"
		cmclient -v flush GETV "$route_obj.X_ADB_OptionFlush"
		echo "        route $prefix {"
		case "$lifetime" in
		"") ;;
		"-1") echo "                AdvRouteLifetime infinity;" ;;
		*) echo "                AdvRouteLifetime $lifetime;" ;;
		esac
		case "$pref" in
		"Low") echo "                AdvRoutePreference low;" ;;
		"Medium") echo "                AdvRoutePreference medium;" ;;
		"High") echo "                AdvRoutePreference high;" ;;
		esac
		case "$flush" in
		"true") echo "                RemoveRoute on;" ;;
		"false") echo "                RemoveRoute off;" ;;
		esac
		echo "        };"
	done
	cmclient -v objs GETO "$2.Option.*.[Enable=true].[Tag=25]"
	create_intf_subentry "$objs" "$3" RDNSS AdvRDNSSLifetime FlushRDNSS
	if [ -z "$objs" ]; then
		local upstreams dns
		cmclient -v upstreams GETO "Device.IP.Interface.[X_ADB_Upstream=true]"
		tmp=""
		for upstreams in $upstreams; do
			tmp="${tmp:+$tmp }$upstreams"
		done
		cmclient -v dns GETV "Device.DNS.Relay.Forwarding.[Status=Enabled].[Type=DHCPv6].[Interface<$tmp].DNSServer"
		if [ -n "$dns" ]; then
			echo -n "	RDNSS"
			for dns in $dns; do
				echo -n " $dns"
			done
			echo " { };"
		fi
	fi
	cmclient -v objs GETO "$2.Option.*.[Enable=true].[Tag=31]"
	create_intf_subentry "$objs" "$3" DNSSL AdvDNSSLLifetime FlushDNSSL
	echo "};"
}
create_radvd_config_file() {
	local del_obj="$1" del_opt="$2" objs
	cmclient -v objs GETO "Device.RouterAdvertisement.InterfaceSetting.*.[Enable=true]"
	for n in $objs; do
		[ -n "$del_obj" -a "$del_obj" = "$n" ] && continue
		cmclient -v ipif GETV $n.Interface
		[ -z "$ipif" ] && continue
		help_lowlayer_ifname_get ifname "$ipif"
		[ -z "$ifname" ] && continue
		create_entry_for_intf "$ifname" "$n" "$del_opt"
	done
}
restart_radvd_process() {
	local if_path="$1" opt_path="$2" pid=
	create_radvd_config_file "$if_path" "$opt_path" >"$file"
	read -r pid </var/run/radvd.pid
	[ -n "$pid" -a -d "/proc/$pid" ] && kill -HUP "$pid" || radvd
	cmclient SETE "Device.RouterAdvertisement.InterfaceSetting.*.[Enable=true].[Interface!].Status" 'Enabled'
	cmclient SETE "Device.RouterAdvertisement.InterfaceSetting.*.[Enable=true].[Interface=].Status" 'Error_Misconfigured'
	cmclient SETE "Device.RouterAdvertisement.InterfaceSetting.*.[Enable!true].Status" 'Disabled'
	return 0
}
hup_radvd_process() {
	local del_ifs="$1" del_opt="$2" pid
	read -r pid </var/run/radvd.pid
	if [ ${#pid} -ne 0 -a -d "/proc/$pid" ]; then
		create_radvd_config_file "$del_ifs" "$del_opt" >"$file"
		kill -HUP "$pid"
	fi
}
stop_radvd_process() {
	[ -f /var/run/radvd.pid ] && killall radvd
	cmclient SETE 'Device.RouterAdvertisement.InterfaceSetting.*.Status' 'Disabled'
	return 0
}
need_radvd_process() {
	local ra_enb="$1" ra_ifs="$2" ra_ifs_enb="$3" ra_ifs_if="$4" tmp
	cmclient -v tmp GETV 'Device.IP.IPv6Enable'
	[ "$tmp" != 'true' ] && return 1
	[ ${#ra_enb} -eq 0 ] && cmclient -v ra_enb GETV 'Device.RouterAdvertisement.Enable'
	[ "$ra_enb" != 'true' ] && return 1
	if [ ${#ra_ifs} -eq 0 ]; then
		cmclient -v tmp GETO "Device.RouterAdvertisement.InterfaceSetting.*.[Enable=true].[Interface!]"
		[ ${#tmp} -ne 0 ] && return 0
	else
		[ "$ra_ifs_enb" = 'true' -a ${#ra_ifs_if} -ne 0 ] && return 0
		cmclient -v tmp GETO "Device.RouterAdvertisement.InterfaceSetting.*.[Enable=true].[Interface!]"
		for tmp in $tmp; do
			[ "$tmp" != "$ra_ifs" ] && return 0
		done
	fi
	return 1
}
service_delete() {
	case "$obj" in
	Device.RouterAdvertisement.InterfaceSetting.*.Option.*)
		hup_radvd_process '' "$obj"
		;;
	Device.RouterAdvertisement.InterfaceSetting.*)
		need_radvd_process '' "$obj" 'false' '' &&
			restart_radvd_process "$obj" '' ||
			stop_radvd_process
		;;
	esac
}
service_config() {
	case "$obj" in
	Device.RouterAdvertisement.InterfaceSetting.*.Option.*)
		[ "$newEnable" = 'true' -o "$changedEnable" = 1 ] &&
			hup_radvd_process '' ''
		;;
	Device.RouterAdvertisement.InterfaceSetting.*)
		if [ "$newEnable" = 'true' -o "$changedEnable" = 1 ]; then
			need_radvd_process '' "$obj" "$newEnable" "$newInterface" &&
				restart_radvd_process '' '' ||
				stop_radvd_process
		fi
		;;
	Device.RouterAdvertisement)
		if [ "$newEnable" = 'true' -o "$changedEnable" = 1 ]; then
			need_radvd_process "$newEnable" '' '' '' &&
				restart_radvd_process '' '' ||
				stop_radvd_process
		fi
		;;
	esac
}
service_get() {
	local obj="$1" param="$2"
	case "$param" in
	*"Prefixes")
		radvd_get_prefix_list "$obj"
		return
		;;
	esac
	echo
}
case "$op" in
s)
	service_config
	;;
d)
	service_delete
	;;
g)
	for arg; do # Arg list as separate words
		service_get "$obj" "$arg"
	done
	;;
esac
exit 0
