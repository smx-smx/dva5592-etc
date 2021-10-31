#!/bin/sh
AH_NAME="TR098_ADD_ATMLinkType"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098()
{
local tr98obj=""
if [ "$newLinkType" = "$oldLinkType" ]; then
return
fi
if [ "$newLinkType" = "EoA" ]; then
tr98obj=`cmclient GETV "$obj.$PARAM_TR098"`
if [ -n "$tr98obj" ]; then
help98_add_bridge_availablelist "${tr98obj%.WANDSLLinkConfig}" "WANInterface"
fi
fi
}
case "$op" in
"s")
service_align_tr098
;;
esac
exit 0
