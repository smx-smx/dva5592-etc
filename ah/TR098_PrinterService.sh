#!/bin/sh
AH_NAME="TR098_PrinterService"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_get() {
	local obj98="$1"
	local param98="$2"
	local value98=""
	case "$param98" in
	"PrintQueueLength")
		job_len=0
		for i in $(cmclient GETO "$found_obj.PrintJob.*.[Status=Queued]"); do
			let "job_len += 1"
		done
		for i in $(cmclient GETO "$found_obj.PrintJob.*.[Status=Spooling]"); do
			let "job_len += 1"
		done
		for i in $(cmclient GETO "$found_obj.PrintJob.*.[Status=Printing]"); do
			let "job_len += 1"
		done
		value98="$job_len"
		;;
	*) ;;

	esac
	echo "$value98"
}
found_obj=$(cmclient GETV "$obj.X_ADB_TR181Name")
case "$op" in
"a")
	local tr181obj=$(help98_add_tr181obj "$obj" "Device.Services.X_ADB_PrinterService.PrinterDevice")
	cmclient SET "$obj.$PARAM_TR181" "$tr181obj" >/dev/null
	;;
"d")
	if [ -n "$found_obj" ]; then
		help181_del_object "$found_obj"
	fi
	;;
"g")
	if [ -n "$found_obj" ]; then
		for arg; do # Arg list as separate words
			service_get "$obj" "$arg"
		done
	else
		for arg; do # Arg list as separate words
			echo ""
		done
	fi
	;;
"s")
	if [ -n "$found_obj" ]; then
		if [ "$changedRemoveQueue" = "1" ]; then
			cmclient SET "$found_obj.PrintJob.*.Cancel" "true"
		fi
	fi
	;;
esac
exit 0
