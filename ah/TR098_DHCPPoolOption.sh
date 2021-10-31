#!/bin/sh
AH_NAME="DHCPPoolOption"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_add()
{
local subref=""
local tr181obj=""
local subobj=${obj%.*}
subobj=${subobj%.*}
subref=`cmclient GETV "$subobj.X_ADB_TR181Name"`
if [ -n "$subref" ]; then
tr181obj=`help98_add_tr181obj "$obj" "$subref.Option"`
cmclient SET "$obj.$PARAM_TR181" "$tr181obj" > /dev/null
fi
}
service_delete()
{
local tr181ref="$1"
help181_del_object "$tr181ref"
}
case "$op" in
"a")
service_add
;;
"d")
local found_obj=`cmclient GETV "$obj.X_ADB_TR181Name"`
if [ -n "$found_obj" ]; then
service_delete "$found_obj"
fi
;;
esac
exit 0
