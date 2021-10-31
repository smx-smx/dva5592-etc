#!/bin/sh
help_host_delete() {
	local host="$1"
	cmclient DEL "Device.ManagementServer.ManageableDevice.[Host,${host}]"
	cmclient DEL "Device.X_ADB_ParentalControl.RestrictedHosts.Host.[HostID=${host##*.}]"
	cmclient DEL "$host"
}
help_host_cleanup() {
	local now hrp limit host mhc lup hc nlup
	cmclient -v hrp GETV "Device.Hosts.X_ADB_HostRetainPeriod"
	now=$(date +%s)
	if [ $hrp -ge 0 ]; then
		limit=$((now - hrp * 60))
		cmclient -v host GETO "Device.Hosts.Host.[Active=false].[X_ADB_LastUp-${limit}]"
		for host in $host; do
			help_host_delete "$host"
		done
	fi
	cmclient -v mhc GETV "Device.Hosts.X_ADB_MaxHostCount"
	if [ $mhc -ge 0 ]; then
		cmclient -v hc GETV "Device.Hosts.HostNumberOfEntries"
		if [ $hc -gt $mhc ]; then
			cmclient -v lup GETV "Device.Hosts.Host.X_ADB_LastUp"
			lup=$(echo "$lup" | sort)
			set -- $lup
			nlup=$#
			for l; do
				if [ $nlup -gt $mhc ]; then
					cmclient -v host GETO "Device.Hosts.Host.[X_ADB_LastUp=$l]"
					for host in $host; do
						help_host_delete "$host"
						nlup=$((nlup - 1))
					done
				else
					break
				fi
			done
		fi
	fi
}
