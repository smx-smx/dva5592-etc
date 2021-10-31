#!/bin/sh
AH_NAME="TR098_QueueMgmtApp"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
help98_set_qosapp_policer() {
	local _qos98="$1" _qos181="$2" _policer98="$3" _policer181=""
	[ -n "$_policer98" -a "$_policer98" != "-1" ] &&
		cmclient -v _policer181 GETO "Device.QoS.Policer.*.[$PARAM_TR098=InternetGatewayDevice.QueueManagement.Policer.$_policer98]"
	echo -n "$_qos181.DefaultPolicer=$_policer181"
}
help98_get_qosapp_policer() {
	local _policer181="$1" policer98="" retval="-1"
	if [ ${#_policer181} -gt 0 ]; then
		cmclient -v policer98 GETV "$_policer181.$PARAM_TR098"
		[ ${#policer98} -gt 0 ] && retval="${policer98##*.}"
	fi
	echo "$retval"
}
help98_set_qosapp_tc() {
	local _qos98="$1" _qos181="$2" _tc98="$3" buf=""
	if [ -z "$_tc98" -o "$_tc98" = "-1" ]; then
		buf="$_qos181.DefaultTrafficClass=0"
	else
		buf="$_qos181.DefaultTrafficClass=$_tc98"
	fi
	echo -n "$buf"
}
service_set_param() {
	local obj98="$1" param98="$2" _val="$3" buffer=""
	case $param98 in
	"AppDefaultQueue")
		cmclient -v class GETV "$found_obj.DefaultTrafficClass"
		if [ "$class" = "0" ]; then
			inittc="${found_obj##*.}"
			inittc=$((20000 + inittc))
			buffer="$found_obj.DefaultTrafficClass=$inittc"
		else
			inittc="$class"
		fi
		cmclient -v queue_obj GETO Device.QoS.Queue.
		for queue_obj in $queue_obj; do
			cmclient -v theseTrafficClasses_ori GETV "$queue_obj.TrafficClasses"
			theseTrafficClasses=$(echo "$theseTrafficClasses_ori" | tr "," "\n")
			found="no"
			for i in $theseTrafficClasses; do
				[ "$i" = "$inittc" ] && found="yes"
			done
			if [ "${queue_obj##*.}" = "$_val" ] && [ "$found" = "no" ]; then
				theseTrafficClasses_ori=${theseTrafficClasses_ori:+$theseTrafficClasses_ori,}"$inittc"
				buffer=${buffer:+$buffer	}"$queue_obj.TrafficClasses=$theseTrafficClasses_ori"
			fi
			if [ "${queue_obj##*.}" != "$_val" ] && [ "$found" = "yes" ]; then
				theseTrafficClasses_ori=""
				for i in $theseTrafficClasses; do
					[ "$i" != "$inittc" ] && theseTrafficClasses_ori=${theseTrafficClasses_ori:+$theseTrafficClasses_ori,}"$i"
				done
				buffer=${buffer:+$buffer	}"$queue_obj.TrafficClasses=$theseTrafficClasses_ori"
			fi
		done
		;;
	"AppDefaultTrafficClass")
		buffer=$(help98_set_qosapp_tc "$obj" "$found_obj" "$_val")
		;;
	"AppDefaultPolicer")
		buffer=$(help98_set_qosapp_policer "$obj" "$found_obj" "$_val")
		;;
	esac
	setm_params=${setm_params:+$setm_params	}$buffer
}
service_config() {
	setm_params=""
	for i in AppDefaultQueue AppDefaultTrafficClass AppDefaultPolicer; do
		if eval [ \${set${i}:=0} -eq 1 ]; then
			eval service_set_param "$obj" "$i" \"\$new${i}\"
		fi
	done
	if [ -n "$setm_params" ]; then
		cmclient -u "tr098" SETM "$setm_params" >/dev/null
	fi
}
service_get() {
	local obj98="$1" param98="$2" value98="" queue_obj="" theseTrafficClasses="" i=""
	case "$param98" in
	"AppDefaultQueue")
		value98="-1"
		cmclient -v queue_obj GETO "Device.QoS.Queue.[TrafficClasses>$tcClass]"
		for queue_obj in $queue_obj; do
			cmclient -v theseTrafficClasses GETV "$queue_obj".TrafficClasses
			for tc in $(help_tr "," " " "$theseTrafficClasses"); do
				if [ "$tc" = "$tcClass" ]; then
					value98="${queue_obj##*.}"
					break 2
				fi
			done
		done
		;;
	"AppDefaultTrafficClass")
		[ ${#tcClass} -eq 0 ] && value98="-1" || value98="$_tc181"
		;;
	"AppDefaultPolicer")
		help98_get_qosapp_policer "$found_obj"
		return
		;;
	*) ;;

	esac
	echo "$value98"
}
service_add() {
	local tr181obj=$(help98_add_tr181obj "$obj" "Device.QoS.App")
	cmclient SET "$obj.$PARAM_TR181" "$tr181obj" >/dev/null
}
cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
case "$op" in
"a")
	service_add
	;;
"d")
	if [ -n "$found_obj" ]; then
		help181_del_object "$found_obj"
	fi
	;;
"g")
	if [ -n "$found_obj" ]; then
		cmclient -v tcClass GETV "$found_obj.DefaultTrafficClass"
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
		service_config
	fi
	;;
esac
exit 0
