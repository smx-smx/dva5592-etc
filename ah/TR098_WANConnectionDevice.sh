#!/bin/sh
AH_NAME="TR098_WANConnectionDevice"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
service_add()
{
wan_path=${obj%.*}
wan_path=${wan_path%.*}
wan_type=`cmclient GETV "$wan_path.WANCommonInterfaceConfig.WANAccessType"`
if [ "$wan_type" = "Ethernet" ]; then
cmclient ADD "$obj.WANEthernetLinkConfig"
elif [ "$wan_type" = "DSL" ] || [ "$wan_type" = "POTS" ]; then
cmclient ADD "$obj.WANDSLLinkConfig"
cmclient ADD "$obj.WANPTMLinkConfig"
fi
}
case "$op" in
"a")
service_add
;;
esac
exit 0
