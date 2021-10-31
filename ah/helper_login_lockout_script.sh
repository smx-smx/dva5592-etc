#!/bin/sh
exec 1>/dev/null
exec 2>/dev/null
. /etc/ah/helper_functions.sh
do_check() {
local fail_obj="$1" locked auto_unlock_time lock_time delta
cmclient -v locked GETV "$fail_obj.Locked"
if [ "$locked" = "true" ]; then
cmclient -v auto_unlock_time GETV Device.UserInterface.X_ADB_AutomaticUnlockTime
[ $auto_unlock_time -gt 0 ] || return 1
cmclient -v lock_time GETV "$fail_obj.LastLockTime"
lock_time=`help_convert_date "$lock_time" "-u"`
delta=$((`date +%s` - lock_time))
[ $delta -gt $auto_unlock_time ] || return 1
cmclient DEL "$fail_obj"
fi
return 0
}
do_record_common() {
local fail_obj="$1" max_failed="$2" time_now setm_params failed
time_now=`date -u +%FT%TZ`
cmclient -v failed GETV "$fail_obj.FailedLoginAttempts"
failed=$((failed+1))
setm_params="$fail_obj.FailedLoginAttempts=$failed"
setm_params="$setm_params	$fail_obj.LastFailLogin=$time_now"
if [ $failed -ge $max_failed ]; then
setm_params="$setm_params	$fail_obj.LastLockTime=$time_now"
setm_params="$setm_params	$fail_obj.Locked=true"
cmclient SETM "$setm_params"
return 1
fi
cmclient SETM "$setm_params"
return 0
}
do_record_user() {
local user="$1" max_failed="$2" idx fail_obj oldest_fail_objs
cmclient -v idx ADD "Device.UserInterface.X_ADB_FailLog.User.[Username=$user]"
if [ "$idx" = "ERROR #4" ]; then ## CM_REQ_ERR_RES, returned when there are too many objects in Device.UserInterface.X_ADB_FailLog.User.
cmclient -v oldest_fail_objs GETO "Device.UserInterface.X_ADB_FailLog.User.[Locked=false]"
[ ${#oldest_fail_objs} -eq 0 ] && cmclient -v oldest_fail_objs GETO "Device.UserInterface.X_ADB_FailLog.User"
for fail_obj in $oldest_fail_objs; do
cmclient DEL "$fail_obj"
break
done
cmclient -v idx ADD "Device.UserInterface.X_ADB_FailLog.User.[Username=$user]"
fi
if ! do_record_common "Device.UserInterface.X_ADB_FailLog.User.$idx" "$max_failed"; then
logger -t "$service" -p 4 "User $user locked due to exceeded number of trials"
return 1
fi
}
do_record_host() {
local host="$1" max_failed="$2" idx fail_obj oldest_fail_objs
cmclient -v idx ADD "Device.UserInterface.X_ADB_FailLog.Host.[Host=$host]"
if [ "$idx" = "ERROR #4" ]; then ## CM_REQ_ERR_RES, returned when there are too many objects in Device.UserInterface.X_ADB_FailLog.Host.
cmclient -v oldest_fail_objs GETO "Device.UserInterface.X_ADB_FailLog.Host.[Locked=false]"
[ ${#oldest_fail_objs} -eq 0 ] && cmclient -v oldest_fail_objs GETO "Device.UserInterface.X_ADB_FailLog.Host"
for fail_obj in $oldest_fail_objs; do
cmclient DEL "$fail_obj"
break
done
cmclient -v idx ADD "Device.UserInterface.X_ADB_FailLog.Host.[Host=$host]"
fi
if ! do_record_common "Device.UserInterface.X_ADB_FailLog.Host.$idx" "$max_failed"; then
logger -t "$service" -p 4 "Host $host locked due to exceeded number of trials"
return 1
fi
}
service="$1"
username="$2"
ip="$3"
action="$4"
case "$action" in
check)
cmclient -v lockout GETV Device.UserInterface.X_ADB_LockoutType
if help_is_in_list "$lockout" "User"; then
cmclient -v fail_obj GETO "Device.UserInterface.X_ADB_FailLog.User.[Username=$username]"
if ! do_check "$fail_obj"; then
logger -t "$service" -p 4 "Authentication denied for user $username due to exceeded number of trials."
exit 1
fi
fi
if [ -n "$ip" ] && help_is_in_list "$lockout" "Host"; then
cmclient -v fail_obj GETO "Device.UserInterface.X_ADB_FailLog.Host.[Host=$ip]"
if ! do_check "$fail_obj"; then
logger -t "$service" -p 4 "Authentication denied for host $ip due to exceeded number of trials."
exit 2
fi
fi
;;
fail)
cmclient -v max_failed GETV Device.UserInterface.X_ADB_MaxFailedLoginAttempts
[ $max_failed -eq 0 ] && exit 0
cmclient -v lockout GETV Device.UserInterface.X_ADB_LockoutType
ret="0"
if [ -n "$ip" ] && help_is_in_list "$lockout" "Host"; then
do_record_host "$ip" "$max_failed" || ret="2"
fi
if help_is_in_list "$lockout" "User"; then
do_record_user "$username" "$max_failed" || ret="1"
fi
exit "$ret"
;;
success)
cmclient DEL "Device.UserInterface.X_ADB_FailLog.User.[Username=$username]"
cmclient DEL "Device.UserInterface.X_ADB_FailLog.Host.[Host=$ip]"
;;
esac
