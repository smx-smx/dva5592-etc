#!/bin/sh
AH_NAME="TR098_ADD_WiFi"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098()
{
local ap181obj=""
local tr98ref=""
local device_id=""
ap181obj="${obj%.AssociatedDevice.*}"
tr98ref=`cmclient GETV "$ap181obj.$PARAM_TR098"`
device_id=`help181_add_tr98obj "$tr98ref.AssociatedDevice" "$obj"`
cmclient SET  "$obj.$PARAM_TR098" "$tr98ref.AssociatedDevice.$device_id" > /dev/null
}
service_delete_tr098()
{
local tr98ref=""
tr98ref="$newX_ADB_TR098Reference"
if [ -n "$tr98ref" ]; then
help181_del_tr98obj "$tr98ref"
fi
}
case "$op" in
"a")
service_align_tr098
;;
"d")
service_delete_tr098
;;
esac
exit 0
