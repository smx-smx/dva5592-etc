#!/bin/sh
AH_NAME=Time
TIMED=/tmp/ec_time
[ "$user" = "${AH_NAME}" ] && exit 0
execute_time_entry() {
local I=1 obj_act obj_path obj_val
while [ $I -le $newActionNumberOfEntries ]; do
cmclient -v obj_act GETV $obj.Action.$I.Operation
cmclient -v obj_path GETV $obj.Action.$I.Path
cmclient -v obj_val GETV $obj.Action.$I.Value
case "$obj_act" in
Add)
cmclient -u "${AH_NAME}" ADD "$obj_path"
;;
Delete)
case "$obj_path" in
Device.X_ADB_Time*)
cmclient DEL "$obj_path"
;;
*)
cmclient -u "${AH_NAME}" DEL "$obj_path"
;;
esac
;;
Set)
set -f
IFS=","
set -- $obj_path
unset IFS
set +f
for path; do
cmclient -u "${AH_NAME}" SET "$path" "$obj_val"
done
;;
Setm)
set -f
IFS=","
set -- $obj_path
unset IFS
set +f
p=""
for path; do
[ -z "$p" ] && p="$path=$obj_val" || p="${p}	$path=$obj_val"
done
cmclient -u "${AH_NAME}" SETM "$p"
;;
Setv)
cmclient -v obj_val GETV "$obj_val"
set -f
IFS=","
set -- $obj_path
unset IFS
set +f
for path; do
cmclient -u "${AH_NAME}" SET "$path" "$obj_val"
done
;;
Save)
cmclient SAVE
;;
Reboot)
cmclient REBOOT
;;
esac
I=$(($I+1))
done
}
create_time_entry() {
local prefix start delta precision
precision=10
if [ "$newDeadLine" = "0" ]; then
if [ -z "$newOccurrenceMonths" ]; then
newOccurrenceMonths="*"
fi
if [ -z "$newOccurrenceMonthsDays" ]; then
newOccurrenceMonthsDays="*"
fi
if [ -z "$newOccurrenceWeekDays" ]; then
newOccurrenceWeekDays="*"
fi
if [ -z "$newOccurrenceHours" ]; then
newOccurrenceHours="*"
fi
if [ -z "$newOccurrenceMinutes" ]; then
newOccurrenceMinutes="*"
fi
prefix="$newOccurrenceMinutes $newOccurrenceHours $newOccurrenceMonthsDays $newOccurrenceMonths $newOccurrenceWeekDays"
start=`date +%s -D %M-%d-%T $newOccurrenceMonths-$newOccurrenceMonthsDays-$newOccurrenceHours:$newOccurrenceMinutes:00 2>/dev/null`
if [ "$newOccurrenceMonths" = "*" -a "$newOccurrenceMonthsDays" = "*" -a "$newOccurrenceWeekDays" = "*" -a \
"$newOccurrenceHours" = "*" -a "$newOccurrenceMinutes" = "*" ]; then
delta=0
elif [ -n "$start" ]; then
delta=$(($start - $currentTime))
else
delta=$(($precision * 2))
fi
else
if [ -z "$currentTime" ]; then
delta=$newDeadLine
else
start=`date +%s -D %FT%T%z -d "$newLastModified"`
delta=$(($start + $newDeadLine - $currentTime))
[ $delta -lt 1 ] && delta=1
fi
prefix="$delta"
fi
if [ "$newDeadLine" = "0" -a $delta -lt $precision ];  then
if [ "$newType" = "EnforcedAperiodic" ]; then
execute_time_entry
cmclient -u "${AH_NAME}" DEL $obj
return
elif [ "$newType" = "Aperiodic" ]; then
return
fi
fi
if [ "$newDeadLine" = 0 ]; then
echo "$prefix $obj.Fired" > $TIMED/${obj}_${newAlias}
else
echo "$prefix $newType $obj.Fired" > $TIMED/${obj}_${newAlias}
fi
}
if [ "$#" -eq 1 ] && [ "$1" = "init" ]; then
currentTime=`date +%s`
cmclient -v newLastModified GETV Device.Time.CurrentLocalTime
cmclient -v objs GETO X_ADB_Time.Event
for obj in $objs; do
cmclient -v newEnable GETV $obj.Enable
[ "$newEnable" = "false" ] && continue
cmclient -v newType GETV $obj.Type
case "$newType" in
"Aperiodic"|"EnforcedAperiodic")
continue
;;
*)
cmclient -v newAlias GETV $obj.Alias
cmclient -v newDeadLine GETV $obj.DeadLine
cmclient -v newOccurrenceMonths GETV $obj.OccurrenceMonths
cmclient -v newOccurrenceWeekDays GETV $obj.OccurrenceWeekDays
cmclient -v newOccurrenceMonthDays GETV $obj.OccurrenceMonthDays
cmclient -v newOccurrenceHours GETV $obj.OccurrenceHours
cmclient -v newOccurrenceMinutes GETV $obj.OccurrenceMinutes
cmclient -v newActionNumberOfEntries GETV $obj.ActionNumberOfEntries
create_time_entry
cmclient SETE $obj.LastModified $newLastModified
;;
esac
done
exit 0
fi
if [ "$op" = "d" ]; then
rm -f $TIMED/${obj}_${newAlias}
exit
fi
if [ "$newEnable" = "false" ]; then
if [ "$changedEnable" = "1" ]; then
rm -f $TIMED/${obj}_${newAlias}
fi
exit 0
fi
if [ "$setFired" = "1" -a "$newFired" = "true" ]; then
cmclient -v lc GETV Device.Time.CurrentLocalTime
cmclient SETE $obj.LastExpired $lc
execute_time_entry
if [ "$newType" != "Periodic" ]; then
cmclient -u "${AH_NAME}" DEL $obj
[ "$newType" = "PersistentAperiodic" ] && cmclient SAVE
rm -f $TIMED/${obj}_${newAlias}
elif [ "$newDeadLine" -gt 0 ]; then
currentTime=""
create_time_entry
fi
exit 0
fi
[ "$changedEnable" = 0 ] && [ "$changedType" = 0 ] && [ "$setDeadLine" = 0 ] && \
[ "$changedAlias" = 0 ] && [ "$changedOccurrenceMinutes" = 0 ] && \
[ "$changedOccurrenceHours" = 0 ] && [ "$changedOccurrenceWeekDays" = 0 ] && \
[ "$changedOccurrenceMonths" = 0 ] && [ "$changedOccurrenceMonthDays" = 0 ] && exit 0
cmclient -v newLastModified GETV Device.Time.CurrentLocalTime
cmclient SETE $obj.LastModified $newLastModified
currentTime=`date +%s`
[ "$newType" != "Periodic" ] && cmclient SETE $obj.LastExpired ""
[ "$changedAlias" = "1" ] && rm -f $TIMED/${obj}_${oldAlias}
create_time_entry
exit 0
