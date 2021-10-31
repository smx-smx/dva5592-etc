#!/bin/sh
AH_NAME="TR098_LANDeviceHostActive"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
send_arp_request() {
	local found_obj iface ip active="0"
	cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
	cmclient -v ip GETV "$found_obj.IPAddress"
	iface=$(ip route get $ip | sed 's/.*dev\s*//;s/\s.*//;1q')
	if [ -n "$iface" ]; then
		/usr/bin/arping -I $iface -f -c 1 -w 1 $ip >/dev/null
		[ "$?" = "0" ] && active="1"
	fi
	if [ "$active" = "1" ]; then
		cmclient SETE "$found_obj.Active" "true" >/dev/null
	else
		cmclient SETE "$found_obj.Active" "false" >/dev/null
	fi
	echo "$active"
}
case "$op" in
"a") ;;

"d") ;;

"g")
	send_arp_request
	;;
esac
exit 0
