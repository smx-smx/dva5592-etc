#!/bin/sh
AH_NAME="HWSwitch"
[ "$user" = "tr098" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
service_get() {
local path="$1" hw_status
case $path in
*"Status" )
read hw_status < /proc/hwswitch/default/enabled
[ $hw_status -eq 1 ] && echo "Enabled" || echo "Disabled"
;;
esac
}
service_set() {
local item list list_disable new_list_disable new_status hw_status
. /etc/ah/helper_serialize.sh && help_serialize
if [ "$setDisableRequest" = 1 ]; then
item=$newDisableRequest
cmclient -v list_disable GETV "Device.Bridging.X_ADB_HWSwitch.DisableRequestList"
list="${list_disable}"
if ! help_is_in_list "$list_disable" "$item"; then
list="${list_disable}${item},"
fi
cmclient SETE "Device.Bridging.X_ADB_HWSwitch.DisableRequestList" "$list"
cmclient SETE "Device.Bridging.X_ADB_HWSwitch.DisableRequest" ""
elif [ "$setEnableRequest" = 1 ]; then
item=$newEnableRequest
cmclient -v list_disable GETV "Device.Bridging.X_ADB_HWSwitch.DisableRequestList"
new_list_disable=`help_str_replace "${item},"  "" "$list_disable"`
cmclient SETE "Device.Bridging.X_ADB_HWSwitch.DisableRequestList" "$new_list_disable"
cmclient SETE "Device.Bridging.X_ADB_HWSwitch.EnableRequest" ""
fi
cmclient -v list_disable GETV "Device.Bridging.X_ADB_HWSwitch.DisableRequestList"
[ ${#list_disable} -ne 0 ] && new_status=0 || new_status=1
read hw_status < /proc/hwswitch/default/enabled
[ "$hw_status" -ne "$new_status" ] && echo $new_status > /proc/hwswitch/default/enabled
}
case "$op" in
s)
service_set
;;
g)
for arg # Arg list as separate words
do
service_get "$obj.$arg"
done
;;
esac
exit 0
