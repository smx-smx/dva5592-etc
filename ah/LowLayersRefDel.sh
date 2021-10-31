#!/bin/sh
. /etc/ah/helper_functions.sh
if [ $# -eq 1 -a "$op" = "d" ]; then
cmclient -v intf GETO "Device.IP.Interface.[LowerLayers>$obj]"
for intf in $intf; do
help_object_remove_references "$intf.LowerLayers" "$obj"
help_object_remove_references "$intf.X_ADB_ActiveLowerLayer" "$obj"
cmclient -v L1 GETV "$intf.LowerLayers"
cmclient -v L2 GETV "$intf.X_ADB_ActiveLowerLayer"
[ ${#L1} -eq 0 -a ${#L2} -eq 0 ] && cmclient SET "$intf.Enable" false
done
fi
exit 0
