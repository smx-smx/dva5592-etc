#!/bin/sh
AH_NAME="TR098_QueueMgmtClassification"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
help98_resolve_qosiface() {
local _qos98="$1" _qos181="$2" _iface98="$3" _iface181="" _obj98=""
if [ -z "$_iface98" ]; then
if [ -z "$setm_params" ]; then
setm_params="$_qos181.AllInterfaces=true	$_qos181.Interface=$_iface181"
else
setm_params="$setm_params	$_qos181.AllInterfaces=true	$_qos181.Interface=$_iface181"
fi
else
_obj98="${_iface98%.*}"
case "$_obj98" in
$OBJ_IGD.Layer2Bridging* )
cmclient -v _iface181 GETO "Device.Bridging.Bridge.*.Port.*.[ManagementPort=true].[$PARAM_TR098=$_iface98]"
;;
$OBJ_IGD.LANDevice.*.WLANConfiguration* )
cmclient -v _iface181 GETO "Device.WiFi.SSID.*.[$PARAM_TR098=$_iface98]"
;;
* )
cmclient -v _iface181 GETO "Device.**.[$PARAM_TR098=$_iface98]"
;;
esac
if [ -n "$_iface181" ]; then
if [ -z "$setm_params" ]; then
setm_params="$_qos181.Interface=$_iface181	$_qos181.AllInterfaces=false"
else
setm_params="$setm_params	$_qos181.Interface=$_iface181	$_qos181.AllInterfaces=false"
fi
fi
fi
}
help98_set_qospolicer() {
local _qos98="$1" _qos181="$2" _policer98="$3" _policer181=""
if [ -z "$_policer98" ] || [ "$_policer98" = "-1" ]; then
_policer181=""
else
policer98="$OBJ_IGD.QueueManagement.Policer.$_policer98"
cmclient -v _policer181 GETO "Device.QoS.Policer.*.[$PARAM_TR098=$policer98]"
fi
if [ -z "$setm_params" ]; then
setm_params="$_qos181.Policer=$_policer181"
else
setm_params="$setm_params	$_qos181.Policer=$_policer181"
fi
}
help98_set_qosapp() {
local _qos98="$1" _qos181="$2" _app98="$3" _app181=""
if [ -z "$_app98" ] || [ "$_app98" = "-1" ]; then
_app181=""
else
app98="$OBJ_IGD.QueueManagement.App.$_app98"
cmclient -v _app181 GETO "Device.QoS.App.*.[$PARAM_TR098=$app98]"
fi
if [ -z "$setm_params" ]; then
setm_params="$_qos181.App=$_app181"
else
setm_params="$setm_params	$_qos181.App=$_app181"
fi
}
help98_get_qos_policer() {
local _policer181="$1" policer98="" retval="-1"
if [ ${#_policer181} -gt 0 ]; then
cmclient -v policer98 GETV "$_policer181.$PARAM_TR098"
[ ${#policer98} -gt 0 ] && retval="${policer98##*.}"
fi
echo "$retval"
}
service_set_param()
{
local obj98="$1" param98="$2" _val="$3"
case $param98 in
"ClassApp")
help98_set_qosapp "$obj" "$found_obj" "$_val"
;;
"ClassInterface")
help98_resolve_qosiface "$obj" "$found_obj" "$_val"
;;
"ClassPolicer")
help98_set_qospolicer "$obj" "$tr181obj" "$_val"
;;
"ClassQueue")
cmclient -v tclass GETV $found_obj.TrafficClass
cmclient -v queue_obj GETO "Device.QoS.Queue.[TrafficClasses>$tclass]"
for queue_obj in $queue_obj; do
newpar=""
stop="0"
cmclient -v theseTrafficClasses GETV "$queue_obj".TrafficClasses
for tc in `help_tr "," " " "$theseTrafficClasses"`
do
if [ "$tc" = "$tclass" ]; then
if  [ "${queue_obj##*.}" = "$_val" ]; then
stop="1"
break
fi
else
if [ -z "$newpar" ]; then
newpar="$tc"
else
newpar="$newpar,$tc"
fi
fi
done
[ "$stop" = "1" ] && break
if [ "${queue_obj##*.}" = "$_val" ]; then
if [ -z "$setm_params" ]; then
setm_params="$queue_obj.TrafficClasses=$newpar,$tclass"
else
setm_params="$setm_params	$queue_obj.TrafficClasses=$newpar,$tclass"
fi
stop="1"
elif [ "$newpar" != "$theseTrafficClasses" ]; then
if [ -z "$setm_params" ]; then
setm_params="$queue_obj.TrafficClasses=$newpar"
else
setm_params="$setm_params	$queue_obj.TrafficClasses=$newpar"
fi
fi
done
if [ "$stop" != "1" ]; then
cmclient -v theseTrafficClasses GETO "Device.QoS.Queue.$_val"
if [ -n "$theseTrafficClasses" ]; then
cmclient -v theseTrafficClasses GETV "Device.QoS.Queue.$_val.TrafficClasses"
if [ -z "$theseTrafficClasses" ]; then
theseTrafficClasses="$tclass"
else
theseTrafficClasses="$theseTrafficClasses,$tclass"
fi
if [ -z "$setm_params" ]; then
setm_params="Device.QoS.Queue.$_val.TrafficClasses=$theseTrafficClasses"
else
setm_params="$setm_params	Device.QoS.Queue.$_val.TrafficClasses=$theseTrafficClasses"
fi
fi
fi
;;
*)
;;
esac
}
service_get()
{
local obj98="$1" param98="$2" value98="" queue_obj
case "$param98" in
"ClassApp")
cmclient -v value181 GETV "$found_obj.App"
help98_get_qos_policer "$value181"
return
;;
"ClassPolicer")
cmclient -v value181 GETV "$found_obj.Policer"
help98_get_qos_policer "$value181"
return
;;
"ClassQueue")
value98="-1"
cmclient -v tclass GETV $found_obj.TrafficClass
cmclient -v queue_obj GETO "Device.QoS.Queue.[TrafficClasses>$tclass]"
for queue_obj in $queue_obj; do
cmclient -v theseTrafficClasses GETV "$queue_obj".TrafficClasses
for tc in `help_tr "," " " "$theseTrafficClasses"`
do
if [ "$tc" = "$tclass" ]; then
value98="${queue_obj##*.}"
break 2
fi
done
done
;;
*)
;;
esac
echo "$value98"
}
service_config()
{
setm_params=""
for i in ClassApp ClassInterface ClassPolicer ClassQueue
do
if eval [ \${set${i}:=0} -eq 1 ]; then
eval service_set_param "$obj" "$i" \"\$new${i}\"
fi
done
if [ -n "$setm_params" ]; then
cmclient -u "tr098" SETM "$setm_params" > /dev/null
fi
}
service_add()
{
local tr181obj=`help98_add_tr181obj "$obj" "Device.QoS.Classification"`
cmclient SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
}
cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
case "$op" in
"a")
service_add
;;
"d")
[ ${#found_obj} -gt 0 ] && help181_del_object "$found_obj"
;;
"g")
if [ ${#found_obj} -gt 0 ]; then
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
else
for arg # Arg list as separate words
do
echo ""
done
fi
;;
"s")
if [ -n "$found_obj" ]; then
service_config
fi
;;
esac
exit 0
