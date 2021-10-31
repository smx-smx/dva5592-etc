#!/bin/sh
[ "$changedStatus" = 1 ] && . /etc/ah/helper_lastChange.sh && help_lastChange_set "$obj"
[ "$newStatus" != "Up" ] && exit 0
cmclient -v upstream GETV $obj.X_ADB_Upstream
[ "$upstream" = true ] && /etc/ah/Firewall.sh ifchange "$obj"
exit 0
