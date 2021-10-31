#!/bin/sh
AH_NAME="TimeOfDayProfile"
[ "$user" = "${AH_NAME}" ] && exit 0
if [ "$op" = "d" ]; then
id=${obj##*TimeOfDayProfile.}
for rhost in `cmclient GETO Device.X_ADB_ParentalControl.RestrictedHosts.Host.[Profile="$id"]`; do
[ "`cmclient GETV $rhost.Enable`" = "true" -a "`cmclient GETV $rhost.TypeOfRestriction`" = "TIMEOFDAY" ] && cmclient SET "$rhost.Enable" "false" > /dev/null
cmclient SET "$rhost.Profile" "0" > /dev/console
done
fi
exit 0
