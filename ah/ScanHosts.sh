#!/bin/sh
AH_NAME="ScanHosts"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_serialize.sh
. /etc/ah/helper_host.sh
ping_host() {
	local host="$1" mac="$2" ipaddr ip6addr_n ifname
	cmclient -v ipaddr GETV "$host.IPAddress"
	cmclient -v ip6addr_n GETV "$host.IPv6AddressNumberOfEntries"
	cmclient -v ifname GETV "%(%($host.Layer3Interface).LowerLayers).Name"
	if [ ${#ifname} -eq 0 ] || [ ${#ipaddr} -eq 0 -a $ip6addr_n -eq 0 ]; then
		help_host_disconnect "$host" "$ifname" "$mac" "$ipaddr"
		return
	fi
	if ip neigh show dev "$ifname" "$ipaddr" nud reachable | grep "lladdr $mac"; then
		cmclient SETE "$host.X_ADB_LastUp" $(date +%s)
		return
	fi
	if ! arping -q -I "$ifname" -w 1 -c 2 $ipaddr; then
		help_host_disconnect "$host" "$ifname" "$mac" "$ipaddr"
	else
		cmclient SETE "$host.X_ADB_LastUp" $(date +%s)
	fi
}
scan_hosts() {
	local objs mobjs
	cmclient -v objs GETO "Device.Hosts.Host.[AddressSource=DHCP]"
	for h in $objs; do
		cmclient -v dhcp_client GETV "$h.DHCPClient"
		cmclient -v leaseTime GETV "$dhcp_client.IPv4Address.1.X_ADB_LeaseTimeRemaining"
		cmclient -v physAddr GETV "$h.PhysAddress"
		if [ $leaseTime -eq 0 ]; then
			cmclient -v ifname GETV "%(%($h.Layer3Interface).LowerLayers).Name"
			cmclient -v ipaddr GETV "$h.IPAddress"
			[ -z "$ifname" ] && continue
			help_host_disconnect "$h" "$ifname" "$physAddr" "$ipaddr" "true"
			cmclient -v mobjs GETO "Device.ManagementServer.ManageableDevice.[Host=$h]"
			for managObj in $mobjs; do
				cmclient DEL "$managObj"
			done
		else
			ping_host "$h" "$physAddr"
		fi
	done
	cmclient -v objs GETO "Device.Hosts.Host.[AddressSource=Static]"
	for h in $objs; do
		cmclient -v physAddr GETV "$h.PhysAddress"
		ping_host "$h" "$physAddr"
	done
}
create_scan_timer() {
	ALIAS_SCAN_HOSTS="ScanLanHosts"
	TIMER_SCAN_HOSTS="300"
	[ "$user" != "Time" ] && cmclient DEL "Device.X_ADB_Time.Event.[Alias=$ALIAS_SCAN_HOSTS]"
	cmclient -v i ADD "Device.X_ADB_Time.Event"
	eventObj="Device.X_ADB_Time.Event.$i"
	cmclient -v j ADD "$eventObj.Action"
	setm_params="$eventObj.Alias=$ALIAS_SCAN_HOSTS"
	setm_params="$setm_params	$eventObj.Type=Aperiodic"
	setm_params="$setm_params	$eventObj.DeadLine=$TIMER_SCAN_HOSTS"
	setm_params="$setm_params	$eventObj.Action.$j.Operation=Set"
	setm_params="$setm_params	$eventObj.Action.$j.Path=Device.Hosts.X_ADB_ScanHosts"
	setm_params="$setm_params	$eventObj.Action.$j.Value=true"
	cmclient SETM "$setm_params"
	cmclient SET $eventObj.Enable true
	return
}
if [ "$1" = "init" ]; then
	create_scan_timer
	exit 0
fi
case "$op" in
"s")
	if [ "$changedX_ADB_ScanHosts" -eq 1 -a "$newX_ADB_ScanHosts" = "true" ]; then
		(
			scan_hosts
			help_host_cleanup
			cmclient SETE "$obj.X_ADB_ScanHosts" "false"
			create_scan_timer
		) &
	fi
	;;
esac
exit 0
