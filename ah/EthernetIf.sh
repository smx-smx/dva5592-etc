#!/bin/sh
AH_NAME="EthernetIf"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$user" = "InterfaceMonitor" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/target.sh
service_get() {
	local obj="$1" arg="$2"
	case "$arg" in
	"Status")
		cmclient -v ifname GETV "$obj.Name"
		eth_get_link_status "$ifname"
		;;
	LastChange)
		. /etc/ah/helper_lastChange.sh
		help_lastChange_get "$obj"
		;;
	*)
		cmclient -v ifname GETV "${obj%.Stats*}.Name"
		help_get_base_stats "$obj.$arg" "$ifname"
		;;
	esac
}
service_config() {
	case "$obj" in
	*Stats)
		[ "$setX_ADB_Reset" = "1" ] && ethswctl -c test -t 2
		return
		;;
	esac
	[ "$setX_ADB_Reset" = "1" ] &&
		(
			help_serialize
			eth_set_power "$newName" down
			sleep 3
			eth_set_power "$newName" up
		) &
	if [ $changedStatus -eq 1 ]; then
		if [ "$newStatus" = "Down" ]; then
			help_if_link_change "$newName" "$newStatus" "$AH_NAME"
		else
			local _new_status=$(eth_get_link_status "$newName")
			if [ "$newEnable" = "true" -a "$_new_status" = "Up" -a "$user" != "boot" ]; then
				help_if_link_change "$newName" "$newStatus" "$AH_NAME"
			fi
		fi
		exit 0
	fi
	local new_status=$(eth_get_link_status "$newName") link_changed=0
	if [ "$newEnable" = "false" ]; then
		if [ $changedEnable -eq 1 ]; then
			eth_set_power "$newName" down
			link_changed=1
		fi
		new_status="Down"
	else
		if [ "$user" = "CWMP" -a "$setEnable" = "1" -a "$changedEnable" = "0" ]; then
			. /etc/ah/helper_ifname.sh
			help_lowlayer_obj_get tmp '%(Device.ManagementServer.X_ADB_ConnectionRequestInterface)' "$obj"
			[ ${#tmp} -eq 0 ] || exit 0
			unset tmp
		fi
		if [ $changedEnable -eq 1 ]; then
			eth_set_power "$newName" up
		fi
		if [ $setEnable -eq 1 -a "$newUpstream" = "true" ] || [ $changedUpstream -eq 1 ]; then
			eth_set_wan "$newName" "$newUpstream" "true"
			eth_set_egress_tm $newName
		fi
		if [ $changedEnable -eq 1 -o $changedMaxBitRate -eq 1 -o $changedDuplexMode -eq 1 ]; then
			if [ "$newMaxBitRate" = "-1" -o "$newDuplexMode" = "Auto" ]; then
				eth_set_media_type "$newName" Auto
				link_changed=1
			elif [ -n "$newMaxBitRate" -a -n "$newDuplexMode" ]; then
				eth_set_media_type "$newName" "$newMaxBitRate" "$newDuplexMode"
				link_changed=1
			fi
		fi
		if [ $setEnable -eq 1 -a "$user" = "boot" ]; then
			if [ "$newMaxBitRate" != "-1" ]; then
				eth_set_media_type "$newName" "$newMaxBitRate" "$newDuplexMode"
				ethsw_power "$newName" "down"
			fi
		fi
		if [ $setEnable -eq 1 -o $changedMACAddress -eq 1 -a "$user" = "boot" ] &&
			[ "$newMACAddress" != "$(cat /sys/class/net/"$newName"/address 2>/dev/null)" ]; then
			ip link set "$newName" down
			echo "### $AH_NAME: Executing <ip link set $newName address $newMACAddress> ###"
			ip link set "$newName" address "$newMACAddress" || new_status=Error
		fi
		if [ "$new_status" = "Up" -a "$user" != "boot" ]; then
			echo "### $AH_NAME: Executing <ip link set $newName up> ###"
			ip link set "$newName" up || new_status=Error
		fi
	fi
	[ "$user" = "boot" -o "$changedEEEEnable" = 1 ] && [ "$newEEECapability" = "true" ] && eth_eee_set $newName $newEEEEnable
	[ "$new_status" != "$newStatus" -a $link_changed -eq 0 -a "$user" != "boot" ] &&
		cmclient SET -u "${AH_NAME}${obj}" "$obj.Status" "$new_status"
}
case "$op" in
g)
	case "$obj" in
	*"WANEthernetInterfaceConfig"*)
		cmclient -v obj GETV "${obj%.Stats*}.X_ADB_TR181Name.Stats"
		;;
	esac
	for arg; do # Arg list as separate words
		service_get "$obj" "$arg"
	done
	;;
s)
	service_config
	;;
esac
exit 0
