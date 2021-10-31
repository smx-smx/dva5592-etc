#!/bin/sh
#udp:ip-up,ppp,*
#sync:max=1
EH_NAME="PPTP Server UP Event"
object=""
update_client_object() {
	cmclient -v clientId ADD "$object.AssociatedClient"
	echo "### $EH_NAME: SET <$object.AssociatedClient.$clientId.LocalIPAddress> <$IPLOCAL> ###" >/dev/console
	cmclient SET "$object.AssociatedClient.$clientId.LocalIPAddress" "$IPLOCAL"
	echo "### $EH_NAME: SET <$object.AssociatedClient.$clientId.RemoteIPAddress> <$IPREMOTE> ###" >/dev/console
	cmclient SET "$object.AssociatedClient.$clientId.RemoteIPAddress" "$IPREMOTE"
	echo "### $EH_NAME: SET <$object.AssociatedClient.$clientId.Name> <$IFNAME> ###" >/dev/console
	cmclient SET "$object.AssociatedClient.$clientId.Name" "$IFNAME"
	echo "### $EH_NAME: SET <$object.AssociatedClient.$clientId.Status> <Up> ###" >/dev/console
	cmclient SET "$object.AssociatedClient.$clientId.Status" "Up"
}
eventHandler_pptpserver_up() {
	cmclient -v object GETO "Device.X_ADB_VPN.Server.PPTP.*.[Alias=$LINKNAME]"
	if [ "$object" = "" ]; then
		exit 0
	fi
	update_client_object
}
eventHandler_pptpserver_up
