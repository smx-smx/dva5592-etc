#!/bin/sh
AH_NAME="TR098_WPS"
. /etc/ah/helper_functions.sh
service_get() {
	local obj="$1" param98="$2" retVal=0 tr181APobj tr181Robj temp
	temp=${obj%%.WPS*}
	cmclient -v tr181APobj GETV "$temp.X_ADB_TR181_AP"
	cmclient -v tr181Robj GETV "$temp.X_ADB_TR181Name"
	case $param98 in
	SetupLockedState)
		cmclient -v temp GETV "$tr181APobj.WPS.X_ADB_SetupLock"
		if [ "$temp" = "true" ]; then
			retVal="LockedByRemoteManagement"
		else
			cmclient -v temp GETV "$tr181Robj.Name"
			temp=$(hostapd_cli -p /tmp/run/hostapd-$temp wps_ap_pin retryinfo)
			if [ ${#temp} -gt 0 -a $temp -ge 1000 ]; then
				retVal="PINRetryLimitReached"
			else
				cmclient -v temp GETV "$tr181APobj.WPS.X_ADB_ConfigurationState"
				[ "$temp" = "NotConfigured" ] && retVal="LockedByLocalManagement" || retVal="Unlocked"
			fi
		fi
		;;
	esac
	echo "$retVal"
}
case "$op" in
g)
	for arg; do # Arg list as separate words
		service_get "$obj" "$arg"
	done
	;;
esac
exit 0
