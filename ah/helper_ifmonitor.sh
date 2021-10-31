#!/bin/sh
help_ifmonitor_action_exist() {
local monif="$1" event="$2" path="$3" local objs action
cmclient -v objs GETO "Device.X_ADB_InterfaceMonitor.Group.*.Interface.*.[MonitoredInterface>$monif]"
for objs in $objs; do
cmclient -v action GETO "$objs.Action.*.[Event=$event].[Path=$path]"
[ -n "$action" ] && return 0
done
return 1
}