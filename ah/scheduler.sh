#!/bin/sh
AH_NAME="scheduler"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
dayname_to_num() {
	local Sun=0 Mon=1 Tue=2 Wed=3 Thu=4 Fri=5 Sat=6
	eval "$2"=\${$1}
}
num_to_day() {
	local week="Sun Mon Tue Wed Thu Fri Sat" day=$((${1} % 7))
	eval "$2"=$(expr substr "$week" $((day * 4 + 1)) 3)
}
neigh_day_parms() {
	local dname=$1 itime=$2 iday step nDay nParam nTime nIsActive aMidn
	[ "$itime" = "StartTime" ] && step="6" || step="1"
	dayname_to_num "$dname" iday
	num_to_day $((iday + step)) nDay
	[ "$itime" = "StartTime" ] && aMidn=$nDay$dname || aMidn=$dname$nDay
	eval "$3=$nDay"
	[ "$step" = "1" ] && eval nParam=${obj%????}.$nDay.StartTime "$5"="0" || eval nParam=${obj%????}.$nDay.EndTime "$5"="1440"
	cmclient -v nTime GETV "$nParam"
	cmclient -v nIsActive GETV "$profile.$nDay.IsActive"
	eval "$4"=$nParam "$6"=$nTime "$7"=$nIsActive "$8"=$aMidn
}
create_event() {
	local alias=$1 dayname=$2 daymin=$3 value=$4 daynum event action enable ctrlObj ctrlObjXTS ctrlObjTS schedEnable schedXEnable
	dayname_to_num "$dayname" daynum
	daynum=$((daynum + (daymin / 1440)))
	cmclient -v event ADDS Device.X_ADB_Time.Event.[Alias="$alias"]
	event=Device.X_ADB_Time.Event."$event"
	setm="$event.Type=Periodic"
	setm="$setm	$event.OccurrenceWeekDays=$daynum"
	setm="$setm	$event.OccurrenceHours=$((daymin / 60))"
	setm="$setm	$event.OccurrenceMinutes=$((daymin % 60))"
	cmclient SETM "$setm"
	cmclient -v ctrlObjXTS GETO Device.**.[X_ADB_TimeScheduler="$profile"]
	cmclient -v ctrlObjTS GETO Device.**.[TimeScheduler="$profile"]
	for ctrlObj in $ctrlObjXTS $ctrlObjTS; do
		cmclient -v schedXEnable GETV "$ctrlObj.X_ADB_TimeSchedulerEnable"
		cmclient -v schedEnable GETV "$ctrlObj.TimeSchedulerEnable"
		[ "$schedEnable" != "true" -a "$schedXEnable" != "true" ] && continue
		cmclient -v action ADDS "$event".Action.[Path="$ctrlObj".Enable]
		action="$event.Action.$action"
		setm="$action.Operation=Set"
		setm="$setm	$action.Value=$value"
		cmclient SETM "$setm"
	done
	cmclient SET "$event.Enable true"
}
delete_event() {
	local alias=$1
	[ ${#alias} -ne 0 ] && cmclient DEL Device.X_ADB_Time.Event.[Alias="$alias"]
}
time_to_event() {
	local dayname=$1 itime=$2 changedTime oldTime newTime neighDay neighIsActive neighTime neighParam neighMidn notIsActive isActiveToSet aliasMidn midnDay midnState neighIsNotActive
	neigh_day_parms "$dayname" "$itime" neighDay neighParam neighMidn neighTime neighIsActive aliasMidn
	[ "$neighIsActive" = "true" ] && neighIsNotActive="false" || neighIsNotActive="true"
	[ "$newIsActive" = "true" ] && notIsActive="false" || notIsActive="true"
	if [ "$itime" = "StartTime" ]; then
		oldTime=$oldStartTime
		newTime=$newStartTime
		isActiveToSet=$newIsActive
		midnDay=$dayname
		changedTime=$changedStartTime
		[ "$newStartTime" = "0" ] && midnState=$isActiveToSet || midnState=$notIsActive
	else
		oldTime=$oldEndTime
		newTime=$newEndTime
		isActiveToSet=$notIsActive
		midnDay=$neighDay
		changedTime=$changedEndTime
		[ "$neighTime" = "$neighMidn" ] && midnState=$neighIsActive || midnState=$neighIsNotActive
	fi
	if [ "$changedIsActive" = 1 ]; then
		if [ "$itime" = "StartTime" -a "$oldTime" = "0" ] || [ "$itime" = "EndTime" -a "$oldTime" = "1440" ]; then
			if [ "$neighTime" = "$neighMidn" -a "$neighIsActive" = "$newIsActive" ] || [ "$neighTime" != "$neighMidn" -a "$neighIsActive" != "$newIsActive" ]; then
				delete_event "$profile.$aliasMidn"
			else
				create_event "$profile.$aliasMidn" "$midnDay" "0" "$midnState"
			fi
		else
			if [ "$neighTime" != "$neighMidn" -a "$neighIsActive" = "$newIsActive" ] || [ "$neighTime" = "$neighMidn" -a "$neighIsActive" != "$newIsActive" ]; then
				delete_event "$profile.$aliasMidn"
			else
				create_event "$profile.$aliasMidn" "$midnDay" "0" "$midnState"
			fi
			create_event "$obj.$itime" "$dayname" "$oldTime" "$isActiveToSet"
		fi
	fi
	if [ "$changedTime" = 1 ]; then
		if [ "$itime" = "StartTime" -a "$newTime" = "0" ] || [ "$itime" = "EndTime" -a "$newTime" = "1440" ]; then
			if [ "$neighTime" = "$neighMidn" -a "$neighIsActive" = "$newIsActive" ] || [ "$neighTime" != "$neighMidn" -a "$neighIsActive" != "$newIsActive" ]; then
				delete_event "$profile.$aliasMidn"
				delete_event "$obj.$itime"
			else
				create_event "$profile.$aliasMidn" "$midnDay" "0" "$midnState"
				delete_event "$obj.$itime"
			fi
		elif [ "$itime" = "StartTime" -a "$oldTime" = "0" ] || [ "$itime" = "EndTime" -a "$oldTime" = "1440" ]; then
			if [ "$neighTime" = "$neighMidn" -a "$neighIsActive" = "$newIsActive" ] || [ "$neighTime" != "$neighMidn" -a "$neighIsActive" != "$newIsActive" ]; then
				create_event "$obj.$itime" "$dayname" "$newTime" "$isActiveToSet"
				create_event "$profile.$aliasMidn" "$midnDay" "0" "$midnState"
			else
				delete_event "$profile.$aliasMidn"
				create_event "$obj.$itime" "$dayname" "$newTime" "$isActiveToSet"
			fi
		else
			create_event "$obj.$itime" "$dayname" "$newTime" "$isActiveToSet"
		fi
	fi
}
profile_required_state() {
	local profile=$1 nowTime nowDay nowHr nowMin isActv startTime endTime
	nowDay=$(date +%a)
	nowHr=$(date +%H)
	nowMin=$(date +%M)
	nowHr="${nowHr#0}"
	nowMin="${nowMin#0}"
	nowTime=$((nowHr * 60 + nowMin))
	cmclient -v startTime GETV "$profile.$nowDay.StartTime"
	cmclient -v endTime GETV "$profile.$nowDay.EndTime"
	cmclient -v isActv GETV "$profile.$nowDay.IsActive"
	if [ $nowTime -gt $startTime -a $nowTime -lt $endTime ]; then
		eval $2=$isActv
	else
		[ "$isActv" = "true" ] && eval $2="false" || eval $2="true"
	fi
}
switch_controlled_service() {
	local ctrlObjs=$1 leaf=$2 val=$3 ctrlObj event action
	cmclient -v event ADDS Device.X_ADB_Time.Event.[Alias="$ctrlObjs.Ignition"]
	event=Device.X_ADB_Time.Event."$event"
	setm="$event.Type=Aperiodic"
	setm="$setm	$event.DeadLine=1"
	cmclient SETM "$setm"
	for ctrlObj in $ctrlObjs; do
		cmclient -v action ADDS "$event".Action.[Path="$ctrlObj.$leaf"]
		action="$event.Action.$action"
		setm="$action.Operation=Set"
		setm="$setm	$action.Value=$val"
		cmclient SETM "$setm"
	done
	cmclient SET "$event.Enable true"
}
initialise_service_by_scheduler() {
	local nowDay="$1" ctrlObjs="$2" nowState="" servEnable ctrlObj
	profile_required_state ${obj%.$nowDay} nowState
	for ctrlObj in $ctrlObjs; do
		cmclient -v servEnable GETV "$ctrlObj.Enable"
		[ "$nowState" != "$servEnable" ] && switch_controlled_service "$ctrlObj" "Enable" "$nowState"
	done
}
recreate_timers() {
	local setm profileConfig config profile="$1"
	cmclient -v profileConfig GET "$profile."
	cmclient DELE "$profile"
	cmclient ADDE "$profile"
	for config in $profileConfig; do
		setm=$setm$(echo "$config" | tr ';' '=')"	"
	done
	cmclient SETM "$setm"
}
delete_timers() {
	cmclient DEL "Device.X_ADB_Time.Event..[Alias>Device.X_ADB_Time.Scheduler.Profile.]"
}
remove_timer_action() {
	local object=$1
	cmclient DEL "Device.X_ADB_Time.Event..[Alias>Device.X_ADB_Time.Scheduler.Profile.].Action.[Path>$object]."
	cmclient DEL "Device.X_ADB_Time.Event..[Alias>Device.X_ADB_Time.Scheduler.Profile.].[ActionNumberOfEntries=0]"
}
contolled_service_handling() {
	local ctrlObj="$1" currState servEnable cEnable nEnable cScheduler nScheduler cActivated nActivated schedStatus
	get_service_variable_from_enviroment cEnable nEnable cScheduler nScheduler cActivated nActivated
	cmclient -v schedStatus GETV "Device.X_ADB_Time.Scheduler.Status"
	[ "$schedStatus" != "Active" ] && exit 0
	if [ "$cEnable" = "1" -o "$cScheduler" = "1" ]; then
		[ "$nActivated" = "false" ] && return
		if [ "$nEnable" = "true" -a ${#nScheduler} -ne 0 ]; then
			remove_timer_action "$ctrlObj"
			recreate_timers "$nScheduler"
			profile_required_state "$nScheduler" currState
			cmclient -v servEnable GETV "$ctrlObj.Enable"
			[ "$currState" != "$servEnable" ] && switch_controlled_service "$ctrlObj" "Enable" "$currState"
		else
			remove_timer_action "$ctrlObj"
			switch_controlled_service "$ctrlObj" "Enable" "$nActivated"
		fi
	elif [ "$cActivated" = 1 ]; then
		if [ "$nActivated" != "true" ]; then
			remove_timer_action "$ctrlObj"
		else
			if [ ${#nScheduler} -ne 0 -a "$nEnable" = "true" ]; then
				remove_timer_action "$ctrlObj"
				recreate_timers "$nScheduler"
				profile_required_state "$nScheduler" currState
				[ "$currState" != "true" ] && switch_controlled_service "$ctrlObj" "Enable" "$currState"
			fi
		fi
	fi
}
update_day() {
	local profile="" dayname schedStatus
	if [ $newStartTime -ge $newEndTime ]; then
		echo "Scheduler error, StartTime mustn't be greater then EndTime" >>/dev/console
		exit 3
	fi
	profile=${obj%????}
	dayname=${obj##*.}
	cmclient -v ctrlObjXTS GETO Device.**.[X_ADB_TimeScheduler="$profile"].[X_ADB_ServiceActivated="true"].[X_ADB_TimeSchedulerEnable="true"]
	cmclient -v ctrlObjTS GETO Device.**.[TimeScheduler="$profile"].[ServiceActivated="true"].[TimeSchedulerEnable="true"]
	cmclient -v schedStatus GETV Device.X_ADB_Time.Scheduler.Status
	[ ${#ctrlObjXTS} = "0" -a ${#ctrlObjTS} = "0" ] && exit 0
	[ "$schedStatus" != "Active" ] && exit 0
	initialise_service_by_scheduler "$dayname" "$ctrlObjXTS $ctrlObjTS"
	[ "$changedIsActive" = 1 -o "$changedStartTime" = 1 ] && time_to_event "$dayname" "StartTime"
	[ "$changedIsActive" = 1 -o "$changedEndTime" = 1 ] && time_to_event "$dayname" "EndTime"
}
service_add() {
	if [ $newProfileNumberOfEntries -gt $newProfileMaxNumber ]; then
		echo "Scheduler error, max number of profiles is $newProfileMaxNumber" >>/dev/console
		exit 4
	fi
	echo "added new obj=$obj" >>/dev/console
}
service_config() {
	local profiles
	case $obj in
	Device.X_ADB_Time.Scheduler.Profile.*.???)
		update_day
		;;
	Device.X_ADB_Time.Scheduler.Profile.*)
		:
		;;
	Device.X_ADB_Time.Scheduler)
		local ctrlObjXTS ctrlObjTS servEnable
		if [ "$changedStatus" = "1" ]; then
			if [ "$newStatus" = "Active" ]; then
				cmclient -v profiles GETO "$obj.Profile"
				for profil in $profiles; do
					recreate_timers "$profil"
				done
			else
				delete_timers
				cmclient -v ctrlObjXTS GETO "Device.**.[X_ADB_TimeScheduler>Device.X_ADB_Time.Scheduler.Profile.].[X_ADB_ServiceActivated=true].[X_ADB_TimeSchedulerEnable=true]"
				cmclient -v ctrlObjTS GETO "Device.**.[TimeScheduler>Device.X_ADB_Time.Scheduler.Profile.].[ServiceActivated=true].[TimeSchedulerEnable=true]"
				for ctrlObj in $ctrlObjXTS $ctrlObjTS; do
					cmclient -v servEnable GETV "$ctrlObj.Enable"
					[ "$servEnable" != "true" ] && switch_controlled_service "$ctrlObj" "Enable" "true"
				done
			fi
		fi
		;;
	Device.WiFi.Radio.*)
		. /etc/ah/helper_scheduler_wifi.sh
		contolled_service_handling "$obj"
		;;
	*)
		echo "Scheduler error, wooops not covered case obj=$obj" >>/dev/console
		;;
	esac
}
service_delete() {
	local event
	case $obj in
	Device.X_ADB_Time.Scheduler.Profile.*)
		cmclient DEL "Device.X_ADB_Time.Event..[Alias>$obj]"
		cmclient SET Device.**.[X_ADB_TimeScheduler="$obj"].X_ADB_TimeScheduler ""
		cmclient SET Device.**.[TimeScheduler="$obj"].TimeScheduler ""
		;;
	*)
		echo "Scheduler error, wooops not covered case obj=$obj" >>/dev/console
		;;
	esac
}
case "$op" in
a)
	service_add
	;;
s)
	service_config
	;;
d)
	service_delete
	;;
esac
exit 0
