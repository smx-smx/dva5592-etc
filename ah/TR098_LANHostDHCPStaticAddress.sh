#!/bin/sh
AH_NAME="LANHostDHCPStaticAddress"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_add()
{
local subref=""
local tr181obj=""
local subobj="${obj%.DHCPStaticAddress*}"
local i=""
local o=""
local ip=""
local ipref=""
local ipif_list=""
local ipif=""
subref=`cmclient GETV "$subobj.X_ADB_TR181Name"`
if [ -z "$subref" ]; then
ipif_list=`cmclient GETV "$subobj.IPInterface.*.X_ADB_TR181Name"`
if [ -n "$ipif_list" ]; then
for o in $ipif_list
do
ip=${o%.*}
ip=${ip%.*}
if [ -z "$ipif" ]; then
ipif="$ip"
else
ipif="$ipif"",""$ip"
fi
done
else
ipif=`help98_add_tr181obj "$subobj" "Device.IP.Interface"`
cmclient SET "$ipif"."Enable" "true" 
fi
set -f
IFS=","
set -- $ipif
unset IFS
set +f
for arg
do
i=`cmclient ADD "Device.DHCPv4.Server.Pool"`
subref="Device.DHCPv4.Server.Pool.$i"
cmclient SET "$subref.Interface" "$arg" 
cmclient SET "$subref.$PARAM_TR098" "$subobj" 
cmclient SET "$subobj.X_ADB_TR181Name" "$subref" 
done
fi	
tr181obj=`help98_add_tr181obj "$obj" "$subref.StaticAddress"`
cmclient SET "$obj.$PARAM_TR181" "$tr181obj"
}
case "$op" in
"a")
service_add
;;
"d")
local found_obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
if [ -n "$found_obj" ]; then
help181_del_object "$found_obj"
fi
;;
esac
exit 0
