#!/bin/sh
AH_NAME="ConnChecker"
case "$obj" in
"Device.Routing.Router.1")
	[ "$newX_ADB_CheckConnectivity" = "true" ] && exit 0
	;;
*)
	[ "$changedStatus" = "0" ] && exit 0
	;;
esac
INOTIFY_DNS_FILE="/tmp/dns/redirect"
LOCAL_NAME="ConnectivityChecker"
cmclient -v found GETO Device.Routing.Router.**.IPv4Forwarding.[DestIPAddress=].[Status=Enabled]
[ ${#found} -gt 0 ] && cmclient SET "Device.X_ADB_ParentalControl.[Enable=true].Reset" $(date) &
exit 0
