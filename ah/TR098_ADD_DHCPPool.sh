#!/bin/sh
AH_NAME="TR098_ADD_DHCPPool"
[ "$user" = "tr098" ] && exit 0
[ "$user" = "NoWiFi" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098()
{
local ipref_new=""
local ipref_old=""
local pool0=""
local tr98ref=""
local tr98ref_old=""
local lanDevice=""
local tr98pool=""
local pool_inst=""
ipref_new="$newInterface"
ipref_old="$oldInterface"
if [ "$ipref_new" = "$ipref_old" ]; then
return
fi
tr98ref=`cmclient GETV "$ipref_new.$PARAM_TR098"`
lanDevice="${tr98ref%.LANHostConfigManagement*}"
if [ -n "$ipref_old" ]; then
tr98ref_old=`cmclient GETV "$ipref_old.$PARAM_TR098"`
case "$tr98ref_old" in
*"LANHostConfigManagement")
tr98pool=`cmclient GETV $obj.X_ADB_TR098Reference`
case "$tr98pool" in
*"LANHostConfigManagement")
;;
*)
if [ -n "$tr98pool" ]; then
help181_del_tr98obj "$tr98pool"
fi
;;
esac
;;
*"LANHostConfigManagement.DHCPConditionalServingPool"*)
help181_del_tr98obj "$tr98ref_old"
;;
*)
;;
esac
fi
case "$tr98ref" in
*"LANHostConfigManagement"*)
pool0=`cmclient GETO DHCPv4.Server.Pool.*.[X_ADB_TR098Reference=$tr98ref]`
if [ -n "$pool0" ]; then
pool_inst=`help181_add_tr98obj "$lanDevice.LANHostConfigManagement.DHCPConditionalServingPool" "$obj"`
cmclient -u "DHCPv4Server" SET "$obj.$PARAM_TR098" "$lanDevice.LANHostConfigManagement.DHCPConditionalServingPool.$pool_inst" > /dev/null
else
cmclient -u "DHCPv4Server" SET "$obj.$PARAM_TR098" "$lanDevice.LANHostConfigManagement" > /dev/null
cmclient SET "$lanDevice.LANHostConfigManagement.X_ADB_TR181Name $obj" > /dev/null
fi
;;
*)
;;
esac
}
service_delete_tr098()
{
local tr98ref=""
tr98ref="$newX_ADB_TR098Reference"
case "$tr98ref" in
*"LANHostConfigManagement")
cmclient SET "$tr98ref.$PARAM_TR181" "" > /dev/null
;;
*)
if [ -n "$tr98ref" ]; then
help181_del_tr98obj "$tr98ref"
fi
;;
esac
}
case "$op" in
"s")
service_align_tr098
;;
"d")
service_delete_tr098
;;
esac
exit 0
