#!/bin/sh
[ "$newCheck" = "false" ] && exit 0
[ "$newCheck" = "true" ] && cmclient SET "X_ADB_ParentalControl.RestrictedHosts.Check" "false"
[ "$user" = "RestrictedHostEntry" ] && exit 0
. /etc/ah/helper_restricted_host.sh
cmclient -v status GETV "X_ADB_ParentalControl.RestrictedHosts.TimeOfDayEnabled"
if [ "$status" = "false" ]; then
cmclient $CHECK_USER SET "X_ADB_ParentalControl.RestrictedHosts.Host.[TypeOfRestriction=TIMEOFDAY].Blocked" "false"
exit 0
fi
day_hr_min=$(date +"%u %H %M %S")
set -- $day_hr_min
week_day=$1
hr=${2#0}
min=${3#0}
secs=${4#0}
day_min=$(($hr*60 + $min))
day_sec=$((day_min*60 + $secs))
prefix="Device.X_ADB_ParentalControl.RestrictedHosts.Host."
suffix=${obj#$prefix}
if [ ${#suffix} -ne 0 -a "$prefix$suffix" = "$obj" ]; then
[ ${#newEnable} -eq 0 ] && cmclient -v newEnable GETV "$obj.Enable"
if [ "$newEnable" = "true" ]; then
[ ${#newTypeOfRestriction} -eq 0 ] && cmclient -v newTypeOfRestriction GETV "$obj.TypeOfRestriction"
[ "$newTypeOfRestriction" = "TIMEOFDAY" ] && RH_OBJS=$obj
fi
else
cmclient -v RH_OBJS GETO "X_ADB_ParentalControl.RestrictedHosts.Host.[Enable=true].[TypeOfRestriction=TIMEOFDAY]."
fi
for host in $RH_OBJS; do
cmclient -v profile_id GETV "$host.Profile"
if [ ${#profile_id} -eq 0 -o "$profile_id" = "0" ]; then
cmclient $CHECK_USER SET "$host.Blocked" "false"
continue
fi
cmclient -v mac GETV "$host.MACAddress"
cmclient -v profile GETO "X_ADB_ParentalControl.RestrictedHosts.TimeOfDayProfile.$profile_id.TimeOfDay.[Day=$week_day]."
if [ ${#profile} -eq 0 ]; then
cmclient $CHECK_USER SET "$host.Blocked" "false"
continue
fi
cmclient -v start GETV "$profile.UsagePeriodBegin"
if [ "$day_sec" -lt "$start" ]; then
cmclient $CHECK_USER SET "$host.Blocked" "true"
continue
fi
cmclient -v end GETV "$profile.UsagePeriodEnd"
if [ "$day_sec" -ge "$end" ]; then
cmclient $CHECK_USER SET "$host.Blocked" "true"
continue
fi
cmclient -v usage_limit GETV "$profile.MaxUsagePerPeriod"
cmclient -v usage GETV "$host.CurrentUsage"
if [ "$usage" -lt "$usage_limit" ]; then
cmclient $CHECK_USER SET "$host.Blocked" "false"
else
cmclient $CHECK_USER SET "$host.Blocked" "true"
fi
done
