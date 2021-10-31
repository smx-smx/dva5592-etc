#!/bin/sh
AH_NAME="TR098_WANDSLLinkConfig"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_set_param() {
local _obj="$1"
local _param="$2"
local _val="$3"
case $_param in
"X_ADB_VLANID")
vlan_obj=`cmclient GETO "Device.Ethernet.VLANTermination.*.[X_ADB_TR098Reference=$_obj]"`
if [ -z "$vlan_obj" ]; then
eth_link=`help98_add_tr181obj "$_obj" "Device.Ethernet.Link"`
help181_set_param "$eth_link.LowerLayers" "$tr181obj"
help181_set_param "$eth_link.Enable" "true"
vlan_obj=`help98_add_tr181obj "$_obj" "Device.Ethernet.VLANTermination"`
help181_set_param "$vlan_obj.LowerLayers" "$eth_link"
fi
help181_set_param "$vlan_obj.VLANID" "$_val"
;;
"LinkType")
if [ "$_val" = "EoA" ]; then
help98_add_bridge_availablelist "${_obj%.WANDSLLinkConfig}" "WANInterface"
fi
;;
"DestinationAddress")
value181=${_val#PVC: *}
value181=${value181#PVC:*}
cmclient SET "$tr181obj.$_param" "$value181" > /dev/null
;;
esac
}
service_config() {
if [ "${setLinkType:=0}" -eq 1 ]; then
service_set_param "$obj" "LinkType" "$newLinkType"
fi
if [ "${X_ADB_VLANID:=0}" -eq 1 ]; then
service_set_param "$obj" "X_ADB_VLANID" "$X_ADB_VLANID"
fi
if [ "${setDestinationAddress:=0}" -eq 1 ]; then
service_set_param "$obj" "DestinationAddress" "$newDestinationAddress"
fi
}
service_add() {
tr181obj=`help98_add_tr181obj "$obj" "Device.ATM.Link"`
cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
help98_link_tr181obj "${obj%%.WANConnectionDevice*}.WANDSLInterfaceConfig" "$tr181obj" "Device.DSL.Channel"
}
service_delete() {
vlan_obj=`cmclient GETO "Device.Ethernet.VLANTermination.*.[X_ADB_TR098Reference=$obj]"`
if [ -n "$vlan_obj" ]; then
eth_link=`cmclient GETV "$vlan_obj.LowerLayers"`
help181_del_object "$vlan_obj"
if [ -n "$eth_link" ]; then
help181_del_object "$eth_link"
fi
fi
help98_del_bridge_availablelist "${obj%.WANDSLLinkConfig*}"
help181_del_object "$tr181obj"
}
service_get() {
local obj="$1"
local param="$2"
case "$param" in
"ModulationType" )
if [ "$tr181status" = "Up" ]; then
xdsl=`xdslctl info --stats`
tmp="${xdsl##*"Mode:			"}"
tmp2="${tmp%%" "*}"
case "$tmp2" in
"ADSL2"* )
echo "ADSL_2plus"
;;
"VDSL"* )
echo "VDSL"
;;
"G.Dmt" )
echo "ADSL_G.dmt"
;;
"G.lite" )
echo "ADSL_G.lite"
;;
*)
echo "$tmp2"
;;
esac
else
echo ""
fi
;;
"ATMReceivedBlocks" )
if [ -d /sys/class/net/"$tr181name" ]; then
tmp=`cat /sys/class/net/"$tr181name"/statistics/rx_packets`
else
tmp="0"
fi
echo "$tmp"
;;
"ATMTransmittedBlocks" )
if [ -d /sys/class/net/"$tr181name" ]; then
tmp=`cat /sys/class/net/"$tr181name"/statistics/tx_packets`
else
tmp="0"
fi
echo "$tmp"
;;
"LinkStatus")
if [ -n "$tr181obj" ]; then
if [ "$tr181status" = "Up" ]; then
echo "Up"
else
echo "Down"
fi
else
echo "Down"
fi
;;
"DestinationAddress")
param181=`cmclient GETV "$tr181obj.$param"`
if [ -z "$param181" ]; then
echo ""
else
echo "PVC: $param181"
fi
;;
*)
echo ""
;;
esac
}
case "$op" in
d)
tr181obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
if [ -n "$tr181obj" ]; then
service_delete
fi
;;
a)
service_add
;;
s)
tr181obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
if [ -n "$tr181obj" ]; then
service_config
fi
;;
g)
tr181obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
tr181name=`cmclient GETV "$tr181obj.Name"`
tr181status=`cmclient GETV "$tr181obj.Status"`
for arg # Arg list as separate words
do 
service_get "$obj" "$arg"
done
;;
esac
exit 0
