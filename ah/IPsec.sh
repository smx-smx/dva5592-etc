#!/bin/sh
AH_NAME="IPsec"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_ipsec.sh
checkdns_reconf_timer() {
	local do_delete
	local do_add
	if [ "$newX_ADB_CheckDNSEnable" = "false" ]; then
		[ "$oldX_ADB_CheckDNSEnable" = "false" ] && return
		do_delete="true"
	else
		if [ "$oldX_ADB_CheckDNSEnable" = "false" ]; then
			do_add="true"
		else
			do_delete="true"
			do_add="true"
		fi
	fi
	[ -n "$do_delete" ] && cmclient DEL Device.X_ADB_Time.Event.[Alias="$IPSEC_TIMER_ALIAS"]
	[ -n "$do_add" ] && ipsec_create_dyndns_timer
}
checkdns_resolve_endpoints() {
	local _profile_obj _next _skip_restart=0
	cmclient -v _profile_obj GETO Device.IPsec.Profile.[X_ADB_ResolvedIP!""]
	for _next in $_profile_obj; do
		local resolved_hn old_resolved_hn hn
		cmclient -v hn GETV $_next.RemoteEndpoints
		[ -z "$hn" ] && continue
		cmclient -v old_resolved_hn GETV $_next.X_ADB_ResolvedIP
		resolved_hn=$(ipsec_resolve_ip "$hn")
		[ "$resolved_hn" != "0.0.0.0" -a "$resolved_hn" != "$old_resolved_hn" ] &&
			cmclient SETE $_next.X_ADB_ResolvedIP "$resolved_hn" &&
			_skip_restart=1
	done
	return $_skip_restart
}
restart_required() {
	[ "$newX_ADB_Reset" = "true" ] && cmclient SETE ${obj}.X_ADB_Reset "false"
	if [ "$newEnable" = "false" ]; then
		[ "$oldEnable" = "true" ] && ipsec_commit "donotstart"
		return 1
	fi
	return 0
}
service_config() {
	local enabled_filters
	help_is_changed "X_ADB_CheckDNSEnable" "X_ADB_CheckDNSFrequency" && checkdns_reconf_timer
	if [ "$newX_ADB_CheckDNSTrigger" = "true" ]; then
		cmclient SETE ${obj}.X_ADB_CheckDNSTrigger "false"
		checkdns_resolve_endpoints && exit 0
	fi
	if restart_required; then ipsec_commit; fi
}
case "$op" in
s)
	service_config
	;;
esac
exit 0
