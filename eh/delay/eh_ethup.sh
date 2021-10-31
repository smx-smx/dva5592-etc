#!/bin/sh
#bcm:*,net,eth*
#sync:skipcycles
. /etc/ah/helper_functions.sh
. /etc/ah/target.sh
cmclient -v ethif GETO "Device.Ethernet.Interface.[Name=$OBJ]"
[ -z "$ethif" ] && exit 0
cmclient -v tmp GETV $ethif.Enable
if [ "$tmp" = "true" ]; then
	[ "$OP" = "add" ] && newStatus="Up" || newStatus="Down"
	eth_set_gmac_mode "$OBJ" "$newStatus"
	cmclient SET "$ethif.Status" "$newStatus"
	eth_set_linkup "$OBJ"
	cmclient -u "EthernetIf" SET "$ethif.X_ADB_MediaType" "$(eth_get_media_type $OBJ)"
	[ "$newStatus" = "Down" ] && help_align_host_table "$ethif"
else
	cmclient SET "$ethif.Status" "Down"
	help_align_host_table "$ethif"
fi
exit 0
