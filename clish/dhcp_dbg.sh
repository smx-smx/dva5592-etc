#!/bin/sh
if [ "$1" = "renew" ]; then
	cmd="Renew"
elif [ "$1" = "release" ]; then
	cmd="X_ADB_Release"
else
	exit 1
fi
cmclient -v wan_list GETO "Device.IP.Interface.[X_ADB_Upstream=true]"
if [ ${#wan_list} -gt 0 ]; then #if WAN exists and setupped
	for wan in $wan_list; do
		cmclient -v status GET "$wan".Status
		if [ "$status" != "${wan}.Status;Up" ]; then
			echo "Warning: Interface is in $status status"
		fi
		cmclient -v dhcpclient GETO "Device.DHCPv4.Client.[Interface=$wan]"
		if [ ${#dhcpclient} -gt 0 ]; then
			cmclient SET "$dhcpclient"."$cmd" true
		else
			echo "DHCP client not found for WAN: $wan"
		fi
	done
else
	echo "WAN interface not found"
fi
exit 0
