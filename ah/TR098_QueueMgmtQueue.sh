#!/bin/sh
AH_NAME="TR098_QueueMgmtQueue"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
help98_resolve_queueiface() {
	local _qos98="$1"
	local _qos181="$2"
	local _iface98="$3"
	local _iface181=""
	local _obj98=""
	if [ ! -n "$_iface98" ]; then
		if [ -z "$setm_params" ]; then
			setm_params="$_qos181.AllInterfaces=true	$_qos181.Interface=$_iface181"
		else
			setm_params="$setm_params	$_qos181.AllInterfaces=true	$_qos181.Interface=$_iface181"
		fi
	else
		_obj98="${_iface98%.*}"
		case "$_obj98" in
		$OBJ_IGD.Layer2Bridging*)
			_iface181=$(cmclient GETO "Device.Bridging.Bridge.*.Port.*.[ManagementPort=true].[$PARAM_TR098=$_iface98]")
			;;
		$OBJ_IGD.LANDevice.*.WLANConfiguration*)
			_iface181=$(cmclient GETO "Device.WiFi.SSID.*.[$PARAM_TR098=$_iface98]")
			;;
		*)
			_iface181=$(cmclient GETO "Device.**.[$PARAM_TR098=$_iface98]")
			;;
		esac
		if [ -n "$_iface181" ]; then
			if [ -z "$setm_params" ]; then
				setm_params="$_qos181.Interface=$_iface181	$_qos181.AllInterfaces=false"
			else
				setm_params="$setm_params	$_qos181.Interface=$_iface181	$_qos181.AllInterfaces=false"
			fi
		fi
	fi
}
service_set_param() {
	local obj98="$1"
	local param98="$2"
	local _val="$3"
	case "$param98" in
	"QueueInterface")
		help98_resolve_queueiface "$obj" "$found_obj" "$_val"
		;;
	*) ;;

	esac
}
service_config() {
	setm_params=""
	for i in QueueInterface; do
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
	local tr181obj=$(help98_add_tr181obj "$obj" "Device.QoS.Queue")
	cmclient SET "$obj.$PARAM_TR181" "$tr181obj" >/dev/null
	;;
"d")
	if [ -n "$found_obj" ]; then
		help181_del_object "$found_obj"
	fi
	;;
"s")
	if [ -n "$found_obj" ]; then
		service_config
	fi
	;;
esac
exit 0
