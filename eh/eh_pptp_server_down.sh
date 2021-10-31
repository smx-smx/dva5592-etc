#!/bin/sh
#udp:ip-down,ppp,*
#sync:max=1
EH_NAME="PPTP Down Event"
object=""
update_client_object() {
	cmclient -v clientObj GETO "$object.AssociatedClient.*.[Name=$IFNAME]"
	cmclient DEL "$clientObj"
}
eventHandler_pptpserver_down() {
	cmclient -v object GETO "Device.X_ADB_VPN.Server.PPTP.*.[Alias=$LINKNAME]"
	if [ "$object" = "" ]; then
		exit 0
	fi
	update_client_object
}
eventHandler_pptpserver_down
