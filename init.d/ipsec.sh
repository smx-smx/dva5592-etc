#!/bin/sh /etc/rc.common

exec 1>/dev/null
exec 2>/dev/null

START=60

. /etc/ah/helper_firewall.sh
. /etc/ah/helper_ipsec.sh

start() {
	help_iptables -t "$FW_TABLE_NATSKIP"
	help_iptables -t "$FW_TABLE_FILTER" -N "$FW_CHAIN_FILTERFWD"
	help_iptables -t "$FW_TABLE_FILTER" -A ForwardAllow -j "$FW_CHAIN_FILTERFWD"
	help_iptables -t "$FW_TABLE_FILTER" -N "$FW_CHAIN_FILTERIN"
	help_iptables -t "$FW_TABLE_FILTER" -A ServicesIn -j "$FW_CHAIN_FILTERIN"

	### Timer is enabled?
	local _dyndns_timer_enabled _dyndns_timer_obj
	cmclient -v _dyndns_timer_enabled GETV "Device.IPsec.X_ADB_CheckDNSEnable"
	cmclient -v _dyndns_timer_obj GETO "Device.X_ADB_Time.Event.[Alias=${IPSEC_TIMER_ALIAS}]"

	[ ${#_dyndns_timer_obj} -eq 0 -a "$_dyndns_timer_enabled" = "true" ] && ipsec_create_dyndns_timer
	
	### XAuth user group
	local current_user xauth_userlist
	cmclient -v current_user GETV Device.Users.User.+.[X_ADB_IPsecAccessCapable=true].Username

	for current_user in $current_user; do xauth_userlist="${xauth_userlist+$xauth_userlist,}${current_user}"; done

	echo "$IPSEC_GROUP:x:$IPSEC_GROUP_ID:$xauth_userlist" >> $GROUP_FILE

	mkdir -p "$SETKEY_INCLUDE_PATH"
	mkdir -p "$RACOON_INCLUDE_PATH"

	cmclient SET -u "${tmpiptablesprefix##*/}" IPsec.X_ADB_Reset "true"
}

