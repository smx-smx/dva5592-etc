#!/bin/sh
AH_NAME="WiFiScheduler"
[ "$user" = "${AH_NAME}" ] && exit 0
ALIAS_ON="WiFiSchedulercOn"
ALIAS_OFF="WiFiSchedulerOff"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize >/dev/null
. /etc/ah/helper_functions.sh
service_remove_event() {
	timeEventReference=$(cmclient GETV "$rm_sched".TimeEventReference)
	set -f
	IFS=","
	set -- $timeEventReference
	unset IFS
	set +f
	for i; do
		cmclient DEL Device.X_ADB_Time.Event."$i". >/dev/null
	done
	cmclient SET -u "${AH_NAME}" "$rm_sched".TimeEventReference "" >/dev/null
}
get_events() {
	eventOn=""
	eventOff=""
	[ -z "$timeEventReference" ] && return
	local evBegin=Device.X_ADB_Time.Event."${timeEventReference%,*}"
	local evEnd=Device.X_ADB_Time.Event."${timeEventReference#*,}"
	if [ "$isDisabledInPeriod" = "false" ]; then
		eventOn="$evBegin"
		eventOff="$evEnd"
	else
		eventOff="$evBegin"
		eventOn="$evEnd"
	fi
	cmclient SET -u "${AH_NAME}" "$obj".TimeEventReference "" >/dev/null
}
service_create_event() {
	[ "$newSchedulerEnabled" = "false" ] && return
	get_events
	if [ -z "$eventOn" ]; then
		indexOn=$(cmclient ADD Device.X_ADB_Time.Event.)
		eventOn="Device.X_ADB_Time.Event.$indexOn"
		cmclient SETM "$eventOn.Alias=$ALIAS_ON$tag	"\
		"$eventOn.Type=Periodic" >/dev/null
		id=$(cmclient ADD "$eventOn".Action.)
		actionOn="$eventOn".Action."$id"
		cmclient SETM "$actionOn.Operation=Set	"\
		"$actionOn.Path=$radio.X_ADB_WirelessScheduler.Machine.Event	"\
		"$actionOn.Value=EV_SCHED_SWITCH_ON" >/dev/null
	else
		cmclient SET "$eventOn".Enable false >/dev/null
		indexOn=${eventOn##*.}
	fi
	if [ -z "$eventOff" ]; then
		indexOff=$(cmclient ADD Device.X_ADB_Time.Event.)
		eventOff="Device.X_ADB_Time.Event.$indexOff"
		cmclient SETM "$eventOff.Alias=$ALIAS_OFF$tag	"\
		"$eventOff.Type=Periodic" >/dev/null
		id=$(cmclient ADD "$eventOff".Action.)
		actionOff="$eventOff".Action."$id"
		cmclient SETM "$actionOff.Operation=Set	"\
		"$actionOff.Path=$radio.X_ADB_WirelessScheduler.Machine.Event	"\
		"$actionOff.Value=EV_SCHED_SWITCH_OFF" >/dev/null
	else
		cmclient SET "$eventOff".Enable false >/dev/null
		indexOff=${eventOff##*.}
	fi
	if [ "$newIsDisabledInPeriod" = "true" ] || [ -z "$newIsDisabledInPeriod" -a "$isDisabledInPeriod" = "true" ]; then
		eventBegin="$eventOff"
		eventEnd="$eventOn"
		indexBegin="$indexOff"
		indexEnd="$indexOn"
	else
		eventBegin="$eventOn"
		eventEnd="$eventOff"
		indexBegin="$indexOn"
		indexEnd="$indexOff"
	fi
	cmclient SET -u "${AH_NAME}" "$wsched".TimeEventReference "$indexBegin","$indexEnd" >/dev/null
}
service_align_event() {
	radio="${obj%%.X_ADB_WirelessScheduler*}"
	case "$obj" in
	*"Basic"*)
		wsched="${obj}"
		tag="Basic"
		timeEventReference="${oldTimeEventReference}"
		isDisabledInPeriod="$oldIsDisabledInPeriod"
		service_create_event
		cmclient SETM "$eventBegin.OccurrenceHours=$((newSchedulerBeginTime / 3600))	" \
		"$eventBegin.OccurrenceMinutes=$(((newSchedulerBeginTime % 3600) / 60))	" \
		"$eventBegin.Enable=true" >/dev/null
		cmclient SETM "$eventEnd.OccurrenceHours=$((newSchedulerEndTime / 3600))	" \
		"$eventEnd.OccurrenceMinutes=$(((newSchedulerEndTime % 3600) / 60))	" \
		"$eventEnd.Enable=true" >/dev/null
		cmclient -u ${AH_NAME} SET "$radio.X_ADB_WirelessScheduler.Advanced.SchedulerEnabled" "false" >/dev/null
		for rm_sched in $(cmclient GETO "$radio.X_ADB_WirelessScheduler.Advanced.Schedule."); do
			service_remove_event
		done
		cmclient -u ${AH_NAME} SETM "$radio.X_ADB_WirelessScheduler.Advanced.Schedule.SchedulerBeginTime=$newSchedulerBeginTime	"\
		"$radio.X_ADB_WirelessScheduler.Advanced.Schedule.SchedulerEndTime=$newSchedulerEndTime" >/dev/null
		;;
	*"Advanced"*)
		case "$obj" in
		*"Advanced")
			sched_obj="$obj.Schedule"
			isDisabledInPeriod=$(cmclient GETV "$obj.IsDisabledInPeriod")
			;;
		*"Advanced.Schedule."*)
			sched_obj="$obj"
			isDisabledInPeriod=$(cmclient GETV "${obj%%.Schedule*}.IsDisabledInPeriod")
			;;
		esac
		for wsched in $(cmclient GETO "$sched_obj."); do
			timeEventReference=$(cmclient GETV "$wsched".TimeEventReference)
			tag="Adv${wsched##*Schedule.}"
			service_create_event
			day=$(cmclient GETV $wsched.Day)
			cmclient SETM "$eventBegin.OccurrenceHours=$(($(cmclient GETV $wsched.SchedulerBeginTime) / 3600))	" \
			"$eventBegin.OccurrenceMinutes=$((($(cmclient GETV $wsched.SchedulerBeginTime) % 3600) / 60))	" \
			"$eventBegin.OccurrenceWeekDays=$day	"\
			"$eventBegin.Enable=true" >/dev/null
			cmclient SETM "$eventEnd.OccurrenceHours=$(($(cmclient GETV $wsched.SchedulerEndTime) / 3600))	" \
			"$eventEnd.OccurrenceMinutes=$((($(cmclient GETV $wsched.SchedulerEndTime) % 3600) / 60))	" \
			"$eventEnd.OccurrenceWeekDays=$day	"\
			"$eventEnd.Enable=true" >/dev/null
		done
		cmclient -u ${AH_NAME} SET "$radio.X_ADB_WirelessScheduler.Basic.SchedulerEnabled" "false" >/dev/null
		rm_sched="$radio.X_ADB_WirelessScheduler.Basic"
		service_remove_event
		;;
	esac
	if [ $(cmclient GETV "$radio.X_ADB_WirelessScheduler.Machine.State") = "STOP" ]; then
		cmclient SET "$radio.X_ADB_WirelessScheduler.Machine.State" "START" >/dev/null
	fi
	cmclient SET "$radio.X_ADB_WirelessScheduler.Machine.Event" "EV_SCHEDULER_ENABLED" >/dev/null
}
service_disable() {
	radio="${obj%%.X_ADB_WirelessScheduler*}"
	case "$obj" in
	*"Basic"*)
		rm_sched="${obj}"
		service_remove_event
		;;
	*"Advanced"*)
		for rm_sched in $(cmclient GETO "$obj.Schedule."); do
			service_remove_event
		done
		;;
	esac
	cmclient SET "$radio.X_ADB_WirelessScheduler.Machine.Event" "EV_SCHEDULER_DISABLED" >/dev/null
}
service_config() {
	if [ "$changedSchedulerEnabled" -eq 1 ] && [ "$newSchedulerEnabled" = "false" ]; then
		service_disable
	elif [ "$newSchedulerEnabled" = "true" ]; then
		service_align_event
	elif [ -z "$newSchedulerEnabled" ]; then
		adv_sched_obj=${obj%%.Schedule*}
		if [ -n "$adv_sched_obj" -a $(cmclient GETV "$adv_sched_obj".SchedulerEnabled) = "true" ]; then
			service_align_event
		fi
	fi
}
case "$op" in
s)
	service_config
	;;
d)
	service_disable
	;;
esac
exit 0
