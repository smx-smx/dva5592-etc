#!/bin/sh
AH_NAME="Stun"
. /etc/ah/helper_functions.sh
check_mandatory_parms()
{
serverAddr="$newSTUNServerAddress"
serverPort="$newSTUNServerPort"
if [ -z "$serverAddr" ]; then
serverAddr="$newURL"
if [ -n "$serverAddr" ]; then
serverAddr="${serverAddr#*://*}"; serverAddr="${serverAddr%%[:/]*}"
else
echo "### $AH_NAME: missing stun server address" > /dev/console
return 0
fi
fi
[ -z "$serverPort" ] && serverPort=3478
return 1
}
get_management_interface_addr()
{
if [ -n "$newX_ADB_ConnectionRequestInterface" ]; then
cmclient -v objs GETO "$newX_ADB_ConnectionRequestInterface".IPv4Address.[Status=Enabled]
for i in $objs; do
cmclient -v mgtIfaceAddr GETV "$i.IPAddress"
[ -n "$mgtIfaceAddr" ] && break
done
fi
if [ -z "$mgtIfaceAddr" ]; then
echo "### $AH_NAME: management interface is down" > /dev/console
return 0
fi
echo "### $AH_NAME: binding on IP Address $mgtIfaceAddr" > /dev/console
return 1
}
start_stund() {
/usr/sbin/stun-client "$serverAddr:$serverPort" \
-i "$mgtIfaceAddr" \
-m "$newSTUNMinimumKeepAlivePeriod" \
-M "$newSTUNMaximumKeepAlivePeriod" \
-u "$newSTUNUsername" \
-w "$newSTUNPassword" \
-d
echo "### $AH_NAME: daemon started" > /dev/console
}
stop_stund()
{
killall -9 stun-client
echo "### $AH_NAME: daemon stopped" > /dev/console
}
need_restart()
{
help_is_changed STUNServerAddress STUNServerPort \
STUNUsername STUNPassword \
STUNMaximumKeepAlivePeriod \
STUNMinimumKeepAlivePeriod STUNEnable && return 0
[ "$setSTUNEnable" = "1" ] && return 0
return 1
}
if [ "$1" = "stop" ]; then
stop_stund
exit 0
fi
if [ "$op" = "s" ]; then
need_restart || exit 0
stop_stund
if [ "$newSTUNEnable" = "true" ]; then
check_mandatory_parms && exit 0
get_management_interface_addr && exit 0
start_stund
fi
fi
exit 0
