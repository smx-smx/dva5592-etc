#!/bin/sh
. /etc/ah/helper_functions.sh
AH_NAME="ChangeProfile"
AH_VERSION="0.1"
do_deviceinfo_set() {
	[ "$changedX_ADB_ProfileType" = "1" ] || return
	confCust="/tmp/cfg/customer_conf"
	if [ -e "$confCust/default.xml" ]; then
		rm -rft "$confCust" "$confCust/default.xml"
		echo "Removing found customer default config" >/dev/console
		cmclient SETEM "Device.DeviceInfo.X_ADB_CustomerDefault=None	Device.DeviceInfo.X_ADB_CustomerDefaultStatus=Inactive"
	fi
	rm -rft /tmp/cfg /tmp/cfg/active_profile
	echo "$newX_ADB_ProfileType" >/tmp/cfg/active_profile
	cmclient RESET
}
case "$obj" in
Device.DeviceInfo)
	case "$op" in
	s)
		do_deviceinfo_set
		;;
	esac
	;;
esac
exit 0
