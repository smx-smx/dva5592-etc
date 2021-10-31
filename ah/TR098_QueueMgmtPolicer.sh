#!/bin/sh
AH_NAME="TR098_QueueMgmtPolicer"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
found_obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
case "$op" in
"a")
local tr181obj=`help98_add_tr181obj "$obj" "Device.QoS.Policer"`
cmclient SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
;;
"d")
if [ -n "$found_obj" ]; then
help181_del_object "$found_obj"
fi
;;
esac
exit 0
