#!/bin/sh
. /etc/ah/helper_functions.sh
ip_obj=$(ip_interface_get "$obj")
if [ "$changedUpstream" = "1" ]; then
	if [ -n "$ip_obj" ]; then
		cmclient -u "IPIf$ip_obj" SET "$ip_obj.X_ADB_Upstream" "$newUpstream"
	fi
fi
if [ "$changedLowerLayers" = "1" ]; then
	case "$newLowerLayers" in
	*"Port"*)
		if [ -n "$ip_obj" ]; then
			br_=${obj%%.Port*}
			if is_pure_bridge "$br_" "" "$newLowerLayers"; then
				cmclient -u "IPIf$ip_obj" SET "$ip_obj.X_ADB_Upstream" "true"
			else
				cmclient -u "IPIf$ip_obj" SET "$ip_obj.X_ADB_Upstream" "false"
			fi
		fi
		;;
	*)
		if is_wan_intf "${newLowerLayers}"; then
			if [ -n "$ip_obj" ]; then
				cmclient -u "IPIf$ip_obj" SET "$ip_obj.X_ADB_Upstream" "true"
			fi
		fi
		;;
	esac
fi
exit 0
