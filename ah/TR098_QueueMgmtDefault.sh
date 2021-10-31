#!/bin/sh
AH_NAME="TR098_QueueMgmtDefault"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
AH_OBJ="$OBJ_IGD.QueueManagement"
help98_set_qosdefpolicer() {
local _qos98="$1" _qos181="$2" _policer98="$3" _policer181=""
if [ -n "$_policer98" -a "$_policer98" != "-1" ]; then
policer98="$OBJ_IGD.QueueManagement.Policer.$_policer98"
cmclient -v _policer181 GETO "Device.QoS.Policer.*.[$PARAM_TR098=$policer98]"
fi
cmclient SET "$_qos181.DefaultPolicer" "$_policer181" > /dev/null
}
help98_set_qosdefqueue() {
local _qos98="$1" _qos181="$2" _queue98="$3" _queue181=""
if [ -n "$_queue98" -a "$_queue98" != "-1" ]; then
queue98="$OBJ_IGD.QueueManagement.Queue.$_queue98"
cmclient -v _queue181 GETO "Device.QoS.Queue.*.[$PARAM_TR098=$queue98]"
fi
cmclient SET "$_qos181.DefaultQueue" "$_queue181" > /dev/null
}
help98_get_qosdef_policer() {
local _policer181="$1" policer98="" retval="-1"
if [ ${#_policer181} -gt 0 ]; then
cmclient -v policer98 GETV "$_policer181.$PARAM_TR098"
[ ${#policer98} -gt 0 ] && retval="${policer98##*.}"
fi
echo "$retval"
}
help98_set_qosdef_tc() {
local _qos98="$1" _qos181="$2" _tc98="$3" tc="0"
[ -n "$_tc98" -a "$_tc98" != "-1" ] && tc="$_tc98"
cmclient SET "$_qos181.DefaultTrafficClass" "$tc" > /dev/null
}
service_set() {
local tr181obj="Device.QoS"
[ "$changedEnable" = "1" -a "$newEnable" = "false" ] && return 7
[ "$changedDefaultTrafficClass" = "1" ] && help98_set_qosdef_tc "$obj" "$tr181obj" "$newDefaultTrafficClass"
[ "$changedDefaultPolicer" = "1" ] && help98_set_qosdefpolicer "$obj" "$tr181obj" "$newDefaultPolicer"
[ "$newDefaultQueue" = "1" ] && help98_set_qosdefqueue "$obj" "$tr181obj" "$newDefaultQueue"
return 0
}
service_get() {
local obj98="$1" param98="$2" paramval="" app_obj
case "$param98" in
DefaultTrafficClass)
cmclient -v paramval GETV Device.QoS."$param98"
[ ${#paramval} -eq 0 ] && paramval="-1"
;;
DefaultPolicer | DefaultQueue )
cmclient -v paramval GETV Device.QoS."$param98"
help98_get_qosdef_policer "$paramval"
return
;;
AvailableAppList )
cmclient -v app_obj GETO Device.QoS.App.
for app_obj in $app_obj; do
cmclient -v protoid GETV $app_obj.ProtocolIdentifier
paramval=${paramval:-$paramval,}$protoid
done
;;
esac
echo "$paramval"
}
case "$op" in
"g")
for arg; do
service_get "$obj" "$arg"
done
;;
"s")
service_set
exit $?
;;
esac
exit 0
