#!/bin/sh
AH_NAME="TR098_ADD_Host"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098() {
	local l1if=""
	local l1old=""
	local tr098lan_device=""
	local tmp_lan=""
	local lan_device=""
	local tr098_oldlan=""
	local tmp_oldlan=""
	local old_lan_device=""
	local tr098_old_host=""
	local host_id=""
	l1if="$newLayer1Interface"
	l1old="$oldLayer1Interface"
	if [ "$l1old" = "_" ]; then
		l1old=""
	elif [ "$l1if" = "_" ]; then
		l1if=""
	fi
	if [ "$l1if" != "$l1old" ]; then
		tr098lan_device=$(cmclient GETV "$l1if.$PARAM_TR098")
		tmp_lan="${tr098lan_device#*LANDevice.[0-9]*}"
		lan_device="${tr098lan_device%$tmp_lan*}"
		if [ -n "$l1old" ]; then
			tr098_oldlan=$(cmclient GETV "$l1old.$PARAM_TR098")
			tmp_oldlan="${tr098_oldlan#*LANDevice.[0-9]*}"
			old_lan_device="${tr098_oldlan%$tmp_oldlan*}"
			if [ "$lan_device" != "$old_lan_device" ]; then
				tr098_old_host=$(cmclient GETV "$obj.$PARAM_TR098")
				if [ -n "$tr098_old_host" ]; then
					help181_del_tr98obj "$tr098_old_host"
				fi
				if [ -n "$lan_device" ]; then
					host_id=$(help181_add_tr98obj "$lan_device.Hosts.Host" "$obj" "${obj##*.}")
					cmclient -u "tr098" SET "$obj.$PARAM_TR098" "$lan_device.Hosts.Host.$host_id" >/dev/null
				fi
			fi
		else
			if [ -n "$lan_device" ]; then
				host_id=$(help181_add_tr98obj "$lan_device.Hosts.Host" "$obj" "${obj##*.}")
				cmclient -u "tr098" SET "$obj.$PARAM_TR098" "$lan_device.Hosts.Host.$host_id" >/dev/null
			fi
		fi
	fi
}
case "$op" in
"s")
	service_align_tr098
	;;
esac
exit 0
