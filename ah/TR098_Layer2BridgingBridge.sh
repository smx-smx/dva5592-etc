#!/bin/sh
AH_NAME="TR098_Layer2BridgingBridge"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_set_param() {
local _param="$1"
local _val="$2"
local set_obj="$found_obj"
local set_param=""
case $_param in
"VLANID")
set_obj=`cmclient GETO "$found_obj.Port.[ManagementPort=true]"`
set_param="PVID"
;;
"BridgeStandard" )
set_param="Standard"
if [ "$_val" = "802.1D" ]; then
_val="802.1D-2004"
else
_val="802.1Q-2005"
fi
;;
*)
;;
esac
if [ -z "$setm_params" ]; then
setm_params="$set_obj.$set_param=$_val"
else
setm_params="$setm_params	$set_obj.$set_param=$_val"
fi
}
service_get() {
local obj="$1" param="$2"
case $param in
"BridgeStandard" )
paramval="${br_standard%"-200"*}"
;;
"VLANID" )
if [ "$br_standard" = "802.1D-2004" ]; then
paramval=0
else
cmclient -v paramval GETV "$found_obj.Port.[ManagementPort=true].PVID"
fi
;;
*)
paramval=""
;;
esac
echo "$paramval"
}
service_config() {
setm_params=""
br_standard=`cmclient GETV "$found_obj.Standard"`
if [ "${setBridgeStandard:=0}" -eq 1 ]; then
service_set_param "BridgeStandard" "$newBridgeStandard"
br_standard="$newBridgeStandard"
fi
if [ "${setVLANID:=0}" -eq 1 ]; then
if [ "$br_standard" = "802.1D-2004" ]; then
return
else
service_set_param "VLANID" "$newVLANID"
fi
fi
if [ -n "$setm_params" ]; then
cmclient -u "tr098" SETM "$setm_params" > /dev/null
fi
}
service_delete() {
mgmt_port=`cmclient GETO "$found_obj.Port.[ManagementPort=true]"`
if [ -n "$mgmt_port" ]; then
help181_del_object "$mgmt_port"
fi
help181_del_object "$found_obj"
}
service_add() {
tr181obj=`help98_add_tr181obj "$obj" "Device.Bridging.Bridge"`
if [ -n "$tr181obj" ]; then
mgmt_port=`help98_add_tr181obj "$obj" "$tr181obj.Port"`
cmclient SET "$mgmt_port.ManagementPort" "true" > /dev/null
cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
fi
}
case "$op" in
a)
service_add
;;
d)
found_obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
if [ -n "$found_obj" ]; then
service_delete
fi
;;
g)
cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
if [ ${#found_obj} -gt 0 ]; then
cmclient -v br_standard GETV "$found_obj.Standard"
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
s)
found_obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
if [ -n "$found_obj" ]; then
service_config
fi
;;
esac
exit 0
