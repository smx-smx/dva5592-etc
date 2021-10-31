#!/bin/sh
service_get() {
	local dhcp_obj chaddr value uptime synch_status rem=-1 date lease
	dhcp_obj=${obj%%.IPv4Address*}
	cmclient -v chaddr GETV "$dhcp_obj.Chaddr"
	eval value=$"new$arg"
	if [ $value -eq 0 ]; then
		rem=0
	elif [ $value -gt 0 ]; then
		cmclient -v synch_status GETV Device.Time.Status
		cmclient -v date GETV $obj.LeaseTimeRemaining
		date=$(echo $date | sed -e s/T/\ / -e s/Z//)
		if [ "$synch_status" = "Synchronized" ] && date +%s -d"$date" >/dev/null; then
			rem=$(($(date +%s -d"$date") - $(date +%s)))
		else
			cmclient -v lease GETV ${obj%%.Client*}.LeaseTime
			read uptime <"/proc/uptime"
			[ $value -gt ${uptime%%.*} ] && value=100
			rem=$((lease - ${uptime%%.*} + value))
		fi
		[ $rem -lt 0 ] && rem=0
	fi
	echo "$rem"
}
service_set() {
	local dhcp_obj chaddr value synch_status date lease=0 lt_remain="9999-12-31T23:59:59Z"
	dhcp_obj=${obj%%.IPv4Address*}
	cmclient -v chaddr GETV "$dhcp_obj.Chaddr"
	value="$newX_ADB_LeaseTimeRemaining"
	if [ $value -ge 0 ]; then
		cmclient -v synch_status GETV Device.Time.Status
		[ $value -ne 0 ] && cmclient -v lease GETV ${obj%%.Client*}.LeaseTime
		if [ "$synch_status" = "Synchronized" ]; then
			value=$(($(date +%s) + lease))
			lt_remain=$(date +%FT%TZ -d@$value)
		else
			value=+$((value + lease))
			lt_remain="0001-01-01T00:00:00Z"
		fi
		echo "$value" >"/tmp/HostsHost_Lease$chaddr"
	fi
	cmclient SET $obj.LeaseTimeRemaining $lt_remain
	[ -x /etc/ah/TA_helper_cm.sh ] && . /etc/ah/TA_helper_cm.sh && austria_save ||
		cmclient SAVE
}
case $op in
g)
	for arg; do # Arg list as separate words
		service_get "$obj" "$arg"
	done
	;;
s)
	service_set
	;;
esac
exit 0
