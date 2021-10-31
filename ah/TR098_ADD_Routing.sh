#!/bin/sh
AH_NAME="TR098_ADD_Routing"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098()
{
local l3forw_id=""
l3forw_id=`help181_add_tr98obj "InternetGatewayDevice.Layer3Forwarding.Forwarding" "$obj"`
cmclient -u "RouterIPv4$obj" SET "$obj.$PARAM_TR098" "InternetGatewayDevice.Layer3Forwarding.Forwarding.$l3forw_id" > /dev/null
}
service_delete_tr098()
{
local tr98ref=""
tr98ref="$newX_ADB_TR098Reference"
if [ -n "$tr98ref" ]; then
help181_del_tr98obj "$tr98ref"
fi
}
service_set_tr098()
{
local tr98ref=""
if [ $changedStaticRoute -eq 0 ]; then
return
fi
cmclient -v tr98ref GETV "$obj.X_ADB_TR098Reference"
case "$tr98ref" in
*"Layer3Forwarding"*)
cmclient -v static_route GETV "$obj.StaticRoute"
[ "$static_route" = "false" ] && cmclient SETS "$tr98ref" 0 || cmclient SETS "$tr98ref" 1
;;
esac
}
case "$op" in
"a")
service_align_tr098
;;
"d")
service_delete_tr098
;;
"s")
service_set_tr098
;;
esac
exit 0
