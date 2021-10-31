#!/bin/sh
AH_NAME="TR098_ADD_QoSQueueStats"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098()
{
local qos181obj=""
local tr98ref=""
local app_id=""
qos181obj="${obj%.QueueStats.*}"
tr98ref=`cmclient GETV "$qos181obj.$PARAM_TR098"`
app_id=`help181_add_tr98obj "$tr98ref.QueueStats" "$obj"`
cmclient SET "$obj.$PARAM_TR098" "$tr98ref.QueueStats.$app_id" > /dev/null
}
service_delete_tr098()
{
local tr98ref=""
local to_delete=""
local queue181=""
tr98ref="$newX_ADB_TR098Reference"
if [ -n "$tr98ref" ]; then
to_delete=1
for queue181 in `cmclient GETO "Device.QoS.QueueStats.*.[$PARAM_TR098=$tr98ref]"`
do
if [ "$queue181" != "$obj" ]; then
to_delete=0
break;
fi
done
if [ "$to_delete" -eq 1 ]; then
help181_del_tr98obj "$tr98ref"
fi
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
