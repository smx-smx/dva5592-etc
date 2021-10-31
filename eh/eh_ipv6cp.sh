#!/bin/sh
#udp:ipv6-*,ppp,*
#sync:max=3
. /etc/ah/helper_serialize.sh
if [ -f "/etc/ah/IPIfIPv6.sh" ]; then
	. /etc/ah/IPv6_helper_functions.sh
else
	exit 0
fi
EH_NAME="IPv6CP"
updateIPv6CPObj() {
	local_ipv6identifier="${ipv6local_short#*"::"}"
	remote_ipv6identifier="${ipv6remote_short#*"::"}"
	echo "### $EH_NAME: SET <$LINKNAME.IPv6CP.LocalInterfaceIdentifier> <$local_ipv6identifier> ###" >>/dev/console
	echo "### $EH_NAME: SET <$LINKNAME.IPv6CP.RemoteInterfaceIdentifier> <$remote_ipv6identifier> ###" >>/dev/console
	cmclient SETM "$LINKNAME.IPv6CP.LocalInterfaceIdentifier=$local_ipv6identifier	$LINKNAME.IPv6CP.RemoteInterfaceIdentifier=$remote_ipv6identifier"
}
eventHandler_ipv6cpLinkUp() {
	ipv6local_short=$(ipv6_short_format $LLLOCAL)
	ipv6remote_short=$(ipv6_short_format $LLREMOTE)
	logger -t "cm" "PPP Interface $IFNAME: IPv6: Up" -p 6
	updateIPv6CPObj
}
updateIPCPObjDown() {
	echo "### $EH_NAME: SET <$LINKNAME.IPv6CP.LocalInterfaceIdentifier> <> ###" >>/dev/console
	echo "### $EH_NAME: SET <$LINKNAME.IPv6CP.RemoteInterfaceIdentifier> <> ###" >>/dev/console
	cmclient SETM "$LINKNAME.IPv6CP.LocalInterfaceIdentifier=	$LINKNAME.IPv6CP.RemoteInterfaceIdentifier="
}
eventHandler_pppLinkDown() {
	logger -t "cm" "PPP Interface $IFNAME: IPv6: Down" -p 6
	updateIPCPObjDown
}
[ "$OP" = "ipv6-up" ] && eventHandler_ipv6cpLinkUp
[ "$OP" = "ipv6-down" ] && eventHandler_pppLinkDown
