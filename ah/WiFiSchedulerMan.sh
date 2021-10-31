#!/bin/sh
AH_NAME="WiFiSchedulerMan"
[ "$user" = "${AH_NAME}" -o "$op" != "s" ] && exit 0
. /etc/ah/helper_functions.sh
ALIAS_CHK_WS="CheckWiFiScheduler"
schedule_periodic_sync_check() {
ws_chk_event=`cmclient GETO "Device.X_ADB_Time.Event.[Alias=$ALIAS_CHK_WS]"`
if [ -z "$ws_chk_event" ]; then
index=`cmclient ADD "Device.X_ADB_Time.Event."`
event="Device.X_ADB_Time.Event.$index"
cmclient SETM 	"$event.Alias=$ALIAS_CHK_WS	"\
"$event.Type=Periodic	"\
"$event.OccurrenceMinutes=0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59" > /dev/null
cmclient ADD "$event.Action" > /dev/null
cmclient SETM	"$event.Action.1.Operation=Set	"\
"$event.Action.1.Path=$obj.Event	"\
"$event.Action.1.Value=EV_CHECK_SYNC" > /dev/null
cmclient SET "$event.Enable true"	> /dev/null
fi
}
unschedule_periodic_sync_check() {
ws_chk_event=`cmclient GETO "Device.X_ADB_Time.Event.[Alias=$ALIAS_CHK_WS]"`
if [ -n "$ws_chk_event" ]; then
cmclient DEL "$ws_chk_event" > /dev/null
fi
}
check_sync_now() {
if [ "`cmclient GETV Device.X_ADB_ParentalControl.RestrictedHosts.TimeOfDayEnabled`" = "true" ]; then
echo "true"
else
echo "false"
fi
}
day_secs_get() {
H=`date +%H`
H=${H#0}
M=`date +%M`
M=${M#0}
S=`date +%S`
S=${S#0}
echo $((H * 3600 + M * 60 + S))
}
check_period_status() {
radio="${obj%%.X_ADB_WirelessScheduler*}"
radio_enable="`cmclient GETV $radio.Enable`"
wsched="$radio.X_ADB_WirelessScheduler"
basic_enabled="`cmclient GETV $wsched.Basic.SchedulerEnabled`"
if [ "$basic_enabled" = "true" ]; then
begin="`cmclient GETV $wsched.Basic.SchedulerBeginTime`"
end="`cmclient GETV $wsched.Basic.SchedulerEndTime`"
is_disabled="`cmclient GETV $wsched.Basic.IsDisabledInPeriod`"
day_sec=$(day_secs_get)
if [ "$begin" -le "$end" ]; then
if [ "$day_sec" -ge "$begin" -a "$day_sec" -le "$end" ]; then
if [ "$is_disabled" = "true" ]; then
sched_wifi_enabled="false"
else
sched_wifi_enabled="true"
fi
else
if [ "$is_disabled" = "true" ]; then
sched_wifi_enabled="true"
else
sched_wifi_enabled="false"
fi
fi
else
if [ "$day_sec" -ge "$end" -a "$day_sec" -le "$begin" ]; then
if [ "$is_disabled" = "true" ]; then
sched_wifi_enabled="true"
else
sched_wifi_enabled="false"
fi
else
if [ "$is_disabled" = "true" ]; then
sched_wifi_enabled="false"
else
sched_wifi_enabled="true"
fi
fi
fi
else
[ "`cmclient GETV $wsched.Advanced.SchedulerEnabled`" !=  "true" ] && return
is_disabled="`cmclient GETV $wsched.Advanced.IsDisabledInPeriod`"
sched_wifi_enabled="$is_disabled"
for sched in `cmclient GETO "$wsched.Advanced.Schedule."`; do
day="`cmclient GETV $sched.Day`"
begin="`cmclient GETV $sched.SchedulerBeginTime`"
end="`cmclient GETV $sched.SchedulerEndTime`"
curr_day=$(date +%w)
[ "$curr_day" != "$day" ] && continue
day_sec=$(day_secs_get)
if [ "$day_sec" -ge "$begin" -a "$day_sec" -le "$end" ]; then
if [ "$is_disabled" = "true" ]; then
sched_wifi_enabled="false"
else
sched_wifi_enabled="true"
fi
fi
break
done
fi
echo "$sched_wifi_enabled"
}
enable_wifi() {
if [ "$newEvent" != "EV_MANUAL_ON" -a "`cmclient GETV Device.WiFi.Radio.1.Enable`" != "true" ]; then
cmclient -u "$AH_NAME" SET "Device.WiFi.Radio.1.Enable" "true" > /dev/null
fi
[ "`cmclient GETV Device.WiFi.SSID.1.Enable`" = "false" ] && cmclient SET "Device.WiFi.SSID.1.Enable" "true" > /dev/null
[ "`cmclient GETV Device.WiFi.AccessPoint.1.Enable`" = "false" ] && cmclient SET "Device.WiFi.AccessPoint.1.Enable" "true" > /dev/null
}
disable_wifi() {
[ "`cmclient GETV Device.WiFi.AccessPoint.1.Enable`" = "true" ] && cmclient SET "Device.WiFi.AccessPoint.1.Enable" "false" > /dev/null
[ "`cmclient GETV Device.WiFi.SSID.1.Enable`" = "true" ] && cmclient SET "Device.WiFi.SSID.1.Enable" "false" > /dev/null
if [ "$newEvent" != "EV_MANUAL_ON" -a "`cmclient GETV Device.WiFi.Radio.1.Enable`" != "false" ]; then
cmclient -u "$AH_NAME" SET "Device.WiFi.Radio.1.Enable" "false" > /dev/null
fi
}
state="`cmclient GETV Device.WiFi.Radio.1.X_ADB_WirelessScheduler.Machine.State`"
case "$state" in
"START")
case "$newEvent" in
"EV_SCHEDULER_ENABLED"|"EV_SCHED_SWITCH_ON"|"EV_CHECK_SYNC")
if [ "`cmclient GETV Device.WiFi.AccessPoint.1.X_Pirelli_WLANProvisioningDone`" = "true" ]; then
sync=$(check_sync_now)
if [ "$sync" = "true" ]; then
unschedule_periodic_sync_check
is_enable_period=$(check_period_status)
if [ "$is_enable_period" = "true" ]; then
cmclient SET "$obj.State" "ON"	> /dev/null
enable_wifi
else
cmclient SET "$obj.State" "OFF"	> /dev/null
disable_wifi
fi
else
enable_wifi
cmclient SET "$obj.State" "UNSYNC"	> /dev/null
schedule_periodic_sync_check
fi
else
disable_wifi
cmclient SET "$obj.State" "UNSYNC"	> /dev/null
schedule_periodic_sync_check
fi
;;
"EV_MANUAL_ON")
if [ "`cmclient GETV Device.WiFi.AccessPoint.1.X_Pirelli_WLANProvisioningDone`" = "true" ]; then
cmclient SET "$obj.State" "ON"	> /dev/null
enable_wifi
fi
;;
"EV_MANUAL_OFF")
cmclient SET "$obj.State" "OFF"	> /dev/null
disable_wifi
;;
"EV_SCHEDULER_DISABLED")
cmclient SET "$obj.State" "STOP"	> /dev/null
;;
*)
;;
esac
;;
"ON")
case "$newEvent" in
	"EV_MANUAL_OFF"|"EV_SCHED_SWITCH_OFF")
cmclient SET "$obj.State" "OFF"	> /dev/null
disable_wifi
;;
"EV_CHECK_SYNC")
unschedule_periodic_sync_check
;;
"EV_UNSYNCHRONIZED")
cmclient SET "$obj.State" "UNSYNC"	> /dev/null
schedule_periodic_sync_check
;;
"EV_SCHEDULER_DISABLED")
cmclient SET "$obj.State" "STOP"	> /dev/null
;;
"EV_SCHEDULER_ENABLED")
is_enable_period=$(check_period_status)
if [ "$is_enable_period" = "false" ]; then
cmclient SET "$obj.State" "OFF"	> /dev/null
disable_wifi
fi
;;
*)
;;
esac
;;
"OFF")
case "$newEvent" in
"EV_MANUAL_ON"|"EV_SCHED_SWITCH_ON")
if [ "`cmclient GETV Device.WiFi.AccessPoint.1.X_Pirelli_WLANProvisioningDone`" = "true" ]; then
cmclient SET "$obj.State" "ON"	> /dev/null
enable_wifi
fi
;;
"EV_CHECK_SYNC")
unschedule_periodic_sync_check
;;
"EV_UNSYNCHRONIZED")
cmclient SET "$obj.State" "UNSYNC"	> /dev/null
if [ "`cmclient GETV Device.WiFi.AccessPoint.1.X_Pirelli_WLANProvisioningDone`" = "true" ]; then
enable_wifi
fi
schedule_periodic_sync_check
;;
"EV_SCHEDULER_DISABLED")
cmclient SET "$obj.State" "STOP"	> /dev/null
;;
"EV_SCHEDULER_ENABLED")
if [ "`cmclient GETV Device.WiFi.AccessPoint.1.X_Pirelli_WLANProvisioningDone`" = "true" ]; then
is_enable_period=$(check_period_status)
if [ "$is_enable_period" = "true" ]; then
cmclient SET "$obj.State" "ON"	> /dev/null
enable_wifi
fi
fi
;;
*)
;;
esac
;;
"UNSYNC")
case "$newEvent" in
"EV_CHECK_SYNC")
if [ "`cmclient GETV Device.WiFi.AccessPoint.1.X_Pirelli_WLANProvisioningDone`" = "true" ]; then
sync=$(check_sync_now)
if [ "$sync" = "true" ]; then
unschedule_periodic_sync_check
is_enable_period=$(check_period_status)
if [ "$is_enable_period" = "true" ]; then
cmclient SET "$obj.State" "ON"	> /dev/null
enable_wifi
else
cmclient SET "$obj.State" "OFF"	> /dev/null
disable_wifi
fi
else
enable_wifi
fi
fi
;;
"EV_MANUAL_ON")
if [ "`cmclient GETV Device.WiFi.AccessPoint.1.X_Pirelli_WLANProvisioningDone`" = "true" ]; then
unschedule_periodic_sync_check
cmclient SET "$obj.State" "ON"	> /dev/null
enable_wifi
fi
;;
"EV_MANUAL_OFF")
unschedule_periodic_sync_check
cmclient SET "$obj.State" "OFF"	> /dev/null
disable_wifi
;;
"EV_SCHEDULER_DISABLED")
unschedule_periodic_sync_check
cmclient SET "$obj.State" "STOP"	> /dev/null
;;
*)
;;
esac
;;
"STOP")
case "$newEvent" in
"EV_CHECK_SYNC")
unschedule_periodic_sync_check
;;
*)
;;
esac
;;
esac
exit 0
