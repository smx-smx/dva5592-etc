#!/bin/sh
AH_NAME="DHCPv6Client"
clientobj="${obj#Device.DHCPv6.Client.}"
clientobj="${clientobj%%.*}"
LOCK_NAME="${AH_NAME}.${clientobj}" # DHCPv6Client.1
CLIENTOBJ="Device.DHCPv6.Client.${clientobj}"
[ "$user" = "$LOCK_NAME" -o "$user" = "eh_ipv6" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize "$LOCK_NAME"
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_functions.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/IPv6_helper_firewall.sh
pidfile_tpl='/tmp/odhcp6c.${ifname}.pid'
conf_tpl='/tmp/odhcp6c.${ifname}.conf'
print_assigned() {
	local entry plt vlt curr_sec
	cmclient -v entry GETV ${1}.${2}
	cmclient -v plt GETV ${1}.PreferredLifetime
	cmclient -v vlt GETV ${1}.ValidLifetime
	curr_sec=$(date -u +"%s")
	plt=$(help_ipv6_lft_to_secs $plt $curr_sec)
	vlt=$(help_ipv6_lft_to_secs $vlt $curr_sec)
	echo "Assigned${2} ${entry},${plt:--1},${vlt:--1}"
}
create_client_config_file() {
	local clientobj="$1"
	local ifname="$2"
	[ -n "$clientobj" ] || return 1
	if [ -z "$ifname" ]; then
		cmclient SET -u "$LOCK_NAME" "$clientobj.Status" Error_Misconfigured
		return 1
	fi
	local tmp="$(mktemp -t /tmp/odhcp6c.conf.XXXXXX)"
	echo "Interface $ifname" >$tmp
	for param in RequestAddresses RequestPrefixes RapidCommit; do
		local val
		cmclient -v val GETV ${clientobj}.${param}
		echo "$param ${val:-off}"
	done >>$tmp
	local ifobj ipa
	cmclient -v ifobj GETV ${clientobj}.Interface
	cmclient -v ipa GETO "${ifobj}.IPv6Address.[Origin=DHCPv6]"
	for ipa in $ipa; do
		print_assigned "$ipa" "IPAddress"
	done >>$tmp
	cmclient -v ipa GETO "${ifobj}.IPv6Prefix.[Origin=PrefixDelegation]"
	for ipa in $ipa; do
		print_assigned "$ipa" "Prefix"
	done >>$tmp
	local val
	cmclient -v val GETV ${clientobj}.RequestedOptions
	if ! help_is_dhcpv6_client_stateful "$clientobj"; then
		help_dhcpv6_client_clean_stateless_options val "$val"
		cmclient SETE "${clientobj}.RequestedOptions" "$val"
	fi
	echo "RequestedOptions ${val:-NONE}" >>$tmp
	cmclient -v val GETV ${clientobj}.X_ADB_EnableRFC7083Compatibility
	echo "X_ADB_EnableRFC7083Compatibility ${val}" >>$tmp
	for param in SuggestedT1 SuggestedT2; do
		local val
		cmclient -v val GETV ${clientobj}.${param}
		echo "$param ${val:--1}"
	done >>$tmp
	local opt
	cmclient -v opt GETO "${clientobj}.SentOption.[Enable=true]"
	for opt in $opt; do
		if [ "$opt" = "$obj" -a "$op" = "d" ]; then
			continue
		fi
		local tag
		cmclient -v tag GETV ${opt}.Tag
		local val
		cmclient -v val GETV ${opt}.Value
		local thetype
		cmclient -v thetype GETV ${opt}.X_ADB_Type
		echo "SentOption ${tag};${thetype};${val}"
	done >>$tmp
	eval "local conf=${conf_tpl}"
	mv "${tmp}" "${conf}"
	cmclient SET -u "$LOCK_NAME" "${clientobj}.Status" Enabled
}
start_client_process() {
	local ifname="$1"
	[ -n "$ifname" ] || return
	eval "local conf=${conf_tpl}"
	eval "local pidfile=${pidfile_tpl}"
	help_ip6tables -A DHCPServicesIn -i $ifname -p udp --dport 546 -j ACCEPT
	help_ip6tables -A DHCPServicesOut -o $ifname -p udp --dport 547 -j ACCEPT
	/bin/odhcp6c -C "$conf" -d -p "$pidfile"
}
signal_client_process() {
	local ifname="$1" signal="$2" auto_mode
	[ -n "$ifname" ] || return
	eval "local pidfile=${pidfile_tpl}"
	[ -f "$pidfile" ] || return
	read pid <$pidfile
	[ -n "$pid" ] || return
	cmclient -v auto_mode GETV ${obj}.X_ADB_AutoMode
	kill "-${signal:-SIGTERM}" "$pid"
	if [ -z "$signal" -o "$signal" = "SIGINT" -o "$signal" = "SIGTERM" ]; then
		rm -f $pidfile
		help_ip6tables -D DHCPServicesIn -i $ifname -p udp --dport 546 -j ACCEPT
		help_ip6tables -D DHCPServicesOut -o $ifname -p udp --dport 547 -j ACCEPT
		[ "$auto_mode" = "true" ] && cmclient SETE "$obj.Enable" "false"
	fi
}
renew_now() {
	local ifname="$1"
	[ -n "$ifname" ] || return
	signal_client_process "$ifname" SIGUSR1
}
stop_client_process_without_release() {
	local ifname=$1 data_from_server i=0
	[ -n "$ifname" ] || return
	eval "local pidfile=${pidfile_tpl}"
	[ -f "$pidfile" ] || return
	read pid <$pidfile
	signal_client_process "$ifname" SIGINT
	[ -n "$pid" ] || return
	while [ $i -lt 42 ]; do
		kill -0 $pid || break
		sleep 0.1
		i=$((i + 1))
	done
}
stop_client_process() {
	local ifname data_from_server i=0
	help_lowlayer_ifname_get ifname "$1"
	[ -n "$ifname" ] || return
	eval "local pidfile=${pidfile_tpl}"
	[ -f "$pidfile" ] || return
	read pid <$pidfile
	signal_client_process "$ifname" "${2:-SIGTERM}"
	[ -n "$pid" ] || return
	while [ $i -lt 420 ]; do
		sleep 0.1
		i=$((i + 1))
		cmclient -v data_from_server GETO "$1.IPv6Prefix.[Origin=PrefixDelegation]"
		[ -n "$data_from_server" ] && continue
		cmclient -v data_from_server GETO "$1.IPv6Address.[Origin=DHCPv6]"
		[ -n "$data_from_server" ] && continue
		break
	done
	i=0
	while [ $i -lt 420 ]; do
		kill -0 $pid || break
		sleep 0.1
		i=$((i + 1))
	done
	help_iptables_all -D DHCPServices --dports 547 -j OutputAllow_LocalServices
}
service_delete() {
	stop_client_process "$oldInterface"
}
is_nothing_changed() {
	for param in Enable Interface RequestAddresses RequestPrefixes RapidCommit SuggestedT1 SuggestedT2 RequestedOptions X_ADB_EnableRFC7083Compatibility; do
		eval "local changed=\${changed${param}}"
		[ $changed -eq 1 ] && return 1
	done
	return 0
}
only_renew_changed() {
	[ $changedRenew -eq 1 ] || return 1
	return is_nothing_changed
}
service_config() {
	local old_ifname ifname ipv6_enable data_from_server i=0
	help_lowlayer_ifname_get old_ifname "$oldInterface"
	help_lowlayer_ifname_get ifname "$newInterface"
	cmclient -v ipv6_enable GETV "Device.IP.IPv6Enable"
	if [ "$newEnable" = "true" -a "$ipv6_enable" = "true" ]; then
		if [ $changedX_ADB_ForceRelease -eq 1 ]; then
			signal_client_process "$old_ifname" SIGUSR2
			cmclient SETE "$obj.X_ADB_ForceRelease" "false"
			while [ $i -lt 420 ]; do
				sleep 0.1
				i=$((i + 1))
				cmclient -v data_from_server GETO "$oldInterface.IPv6Prefix.[Origin=PrefixDelegation]"
				[ -n "$data_from_server" ] && continue
				cmclient -v data_from_server GETO "$oldInterface.IPv6Address.[Origin=DHCPv6]"
				[ -n "$data_from_server" ] && continue
				break
			done
			return
		fi
		if [ $changedInterface -eq 1 ]; then
			stop_client_process "$oldInterface"
		fi
		if only_renew_changed; then
			renew_now "$ifname"
			cmclient SET -u "$LOCK_NAME" "$obj.Renew" "false"
			return
		fi
		eval "local pidfile=${pidfile_tpl}"
		is_nothing_changed && [ -f "$pidfile" ] && return
		stop_client_process "$newInterface"
		create_client_config_file "$obj" "$ifname" && start_client_process "$ifname"
	elif [ $changedEnable -eq 1 -o "$ipv6_enable" = "false" ]; then
		cmclient SETE "$obj.Status" Disabled
		stop_client_process "$oldInterface"
	fi
}
sent_options_change() {
	local clientobj="$1"
	local is_enabled
	cmclient -v is_enabled ${clientobj}.Enable
	if [ "$is_enabled" != "true" ]; then
		return 1
	fi
	local ifobj
	cmclient -v ifobj GETV ${clientobj}.Interface
	if [ -z "$ifobj" ]; then
		cmclient -u "$LOCK_NAME" SET "${clientobj}.Status" Error_Misconfigured
		return 1
	fi
	local ifname
	help_lowlayer_ifname_get ifname $ifobj
	if [ -z "$ifname" ]; then
		cmclient -u "$LOCK_NAME" SET "${clientobj}.Status" Error_Misconfigured
		return 1
	fi
	stop_client_process "$ifobj"
	create_client_config_file "$clientobj" "$ifname" && start_client_process "$ifname"
}
case "$obj" in
Device.DHCPv6.Client.*.SentOption.*)
	sent_options_change "$CLIENTOBJ"
	exit 0
	;;
esac
if [ $setEnable -eq 1 -a "$newX_ADB_AutoMode" = "true" -a "$user" != "eh_ipv6_automode" -a ! -f "$pidfile_tpl" ]; then
	cmclient SETE "$obj.Enable" "false"
	exit 0
fi
if [ "$CLIENTOBJ" = "$obj" ]; then
	case "$op" in
	d)
		service_delete
		;;
	s)
		service_config
		;;
	stop)
		[ -n "$ifname" ] && stop_client_process_without_release "$ifname"
		;;
	esac
fi
exit 0
