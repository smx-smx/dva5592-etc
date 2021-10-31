#!/bin/sh
. /etc/ah/helper_restricted_host.sh
help_serialize RestrictedHostRules > /dev/null
if [ "$op" = "d" -o "$op" = "a" -o "$changedUsagePeriodBegin" = "1" -o "$changedUsagePeriodEnd" = "1" ]; then
verification=$(cmclient GETV Device.X_ADB_ParentalControl.RestrictedHosts.Verification)
occ=$(compute_occurence $verification)
cmclient SET X_ADB_Time.Event.[Alias=CheckRestrictedHost].OccurrenceMinutes $occ > /dev/null
fi
exit 0
