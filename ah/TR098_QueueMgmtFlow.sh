#!/bin/sh
AH_NAME="TR098_QueueMgmtFlow"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
help98_set_qosflow_app() {
	local _qos98="$1"
	local _qos181="$2"
	local _app98="$3"
	local _app181=""
	if [ ! -n "$_app98" ] || [ "$_app98" = "-1" ]; then
		_app181=""
	else
		app98="$OBJ_IGD.QueueManagement.App.$_app98"
		_app181=$(cmclient GETO "Device.QoS.App.*.[$PARAM_TR098=$app98]")
	fi
	echo -n "$_qos181.App=$_app181"
}
help98_set_qosflow_policer() {
	local _qos98="$1"
	local _qos181="$2"
	local _policer98="$3"
	local _policer181=""
	if [ ! -n "$_policer98" ] || [ "$_policer98" = "-1" ]; then
		_policer181=""
	else
		policer98="$OBJ_IGD.QueueManagement.Policer.$_policer98"
		_policer181=$(cmclient GETO "Device.QoS.Policer.*.[$PARAM_TR098=$policer98]")
	fi
	echo -n "$_qos181.Policer=$_policer181"
}
help98_get_qosflow_policer() {
	local _policer181="$1" policer98="" retval="-1"
	if [ ${#_policer181} -gt 0 ]; then
		cmclient -v policer98 GETV "$_policer181.$PARAM_TR098"
		[ ${#policer98} -gt 0 ] && retval="${policer98##*.}"
	fi
	echo "$retval"
}
help98_set_qosflow_tc() {
	local _qos98="$1"
	local _qos181="$2"
	local _tc98="$3"
	local buf=""
	if [ ! -n "$_tc98" ] || [ "$_tc98" = "-1" ]; then
		buf="$_qos181.TrafficClass=0"
	else
		buf="$_qos181.TrafficClass=$_tc98"
	fi
	echo -n "$buf"
}
service_set_param() {
	local obj98="$1"
	local param98="$2"
	local _val="$3"
	local buffer=""
	case "$param98" in
	"AppIdentifier")
		buffer=$(help98_set_qosflow_app "$obj" "$found_obj" "$_val")
		;;
	"FlowQueue")
		class=$(cmclient GETV "$found_obj.TrafficClass")
		if [ "$class" = "0" ]; then
			inittc="${tr181obj##*.}"
			inittc=$((10000 + inittc))
			buffer="$found_obj.TrafficClass=$inittc"
		else
			inittc="$class"
		fi
		for queue_obj in $(cmclient GETO Device.QoS.Queue.); do
			theseTrafficClasses_ori=$(cmclient GETV "$queue_obj".TrafficClasses)
			theseTrafficClasses=$(echo "$theseTrafficClasses_ori" | tr "," "\n")
			found="no"
			for i in $theseTrafficClasses; do
				if [ "$i" = "$inittc" ]; then
					found="yes"
				fi
			done
			if [ "${queue_obj##*.}" = "$_val" ] && [ "$found" = "no" ]; then
				if [ "$theseTrafficClasses_ori" != "" ]; then
					theseTrafficClasses_ori="$theseTrafficClasses_ori","$inittc"
				else
					theseTrafficClasses_ori="$inittc"
				fi
				if [ -z "$buffer" ]; then
					buffer="$queue_obj.TrafficClasses=$theseTrafficClasses_ori"
				else
					buffer="$buffer	$queue_obj.TrafficClasses=$theseTrafficClasses_ori"
				fi
			fi
			if [ "${queue_obj##*.}" != "$_val" ] && [ "$found" = "yes" ]; then
				theseTrafficClasses_ori=""
				for i in $theseTrafficClasses; do
					if [ "$i" != "$inittc" ]; then
						if [ "$theseTrafficClasses_ori" = "" ]; then
							theseTrafficClasses_ori="$i"
						else
							theseTrafficClasses_ori="$theseTrafficClasses_ori","$i"
						fi
					fi
				done
				if [ -z "$buffer" ]; then
					buffer="$queue_obj.TrafficClasses=$theseTrafficClasses_ori"
				else
					buffer="$buffer	$queue_obj.TrafficClasses=$theseTrafficClasses_ori"
				fi
			fi
		done
		;;
	"FlowTrafficClass")
		buffer=$(help98_set_qosflow_tc "$obj" "$found_obj" "$_val")
		;;
	"FlowPolicer")
		buffer=$(help98_set_qosflow_policer "$obj" "$found_obj" "$_val")
		;;
	*) ;;

	esac
	if [ -z "$setm_params" ]; then
		setm_params="$buffer"
	else
		setm_params="$setm_params	$buffer"
	fi
}
service_get() {
	local obj98="$1" param98="$2" value98=""
	case "$param98" in
	"AppIdentifier")
		cmclient -v value181 GETV "$found_obj.App"
		help98_get_qosflow_policer "$value181"
		return
		;;
	"FlowQueue")
		value98="-1"
		cmclient -v tclass GETV $found_obj.TrafficClass
		cmclient -v queue_obj GETO "Device.QoS.Queue.[TrafficClasses>$tclass]"
		for queue_obj in $queue_obj; do
			cmclient -v theseTrafficClasses GETV "$queue_obj".TrafficClasses
			for tc in $(help_tr "," " " "$theseTrafficClasses"); do
				if [ "$tc" = "$tclass" ]; then
					value98="${queue_obj##*.}"
					break 2
				fi
			done
		done
		;;
	"FlowTrafficClass")
		value98="-1"
		cmclient -v value181 GETV "$found_obj.TrafficClass"
		[ ${#value181} -gt 0 ] && value98="$value181"
		;;
	"FlowPolicer")
		cmclient -v value181 GETV "$found_obj.Policer"
		help98_get_qosflow_policer "$value181"
		return
		;;
	*) ;;

	esac
	echo "$value98"
}
service_config() {
	setm_params=""
	for i in AppIdentifier FlowQueue; do
		if eval [ \${set${i}:=0} -eq 1 ]; then
			eval service_set_param "$obj" "$i" \"\$new${i}\"
		fi
	done
	if [ -n "$setm_params" ]; then
		cmclient -u "tr098" SETM "$setm_params" >/dev/null
	fi
}
cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
case "$op" in
"a")
	local tr181obj=$(help98_add_tr181obj "$obj" "Device.QoS.Flow")
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
		service_config
	fi
	;;
esac
exit 0
