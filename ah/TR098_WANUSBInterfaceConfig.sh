#!/bin/sh
AH_NAME="X_ADB_WANUSBInterfaceConfig"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_add() {
obj_found=0
for tr181obj in `cmclient GETO "Device.USB.Interface.[$PARAM_TR098=]"`
do
cmclient SET "$tr181obj.$PARAM_TR098" "$obj" > /dev/null
obj_found=1
break;
done
if [ "$obj_found" -ne 1 ]; then
tr181obj=`help98_add_tr181obj "$obj" "Device.USB.Interface"`
fi
help181_set_param "$tr181obj.Upstream" "true" > /dev/null
cmclient SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
}
service_delete() {
cmclient SET "$tr181obj.$PARAM_TR098" "" > /dev/null
help181_set_param "$tr181obj.Upstream" "false"
}
case "$op" in
a)
service_add
;;
d)
tr181obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
if [ -n "$tr181obj" ]; then
service_delete
fi
;;
esac
exit 0
