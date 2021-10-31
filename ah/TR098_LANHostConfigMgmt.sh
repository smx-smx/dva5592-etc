#!/bin/sh
AH_NAME="LANHostConfigMgmt"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_lookup_param() {
	local _tr098obj="$1" _tr098par="$2"
	[ "$3" != "obj181" ] && local obj181=""
	case "$_tr098par" in
	"UseAllocatedWAN")
		cmclient -v assoc_conn GETV "$_tr098obj.AssociatedConnection"
		if [ -n "$assoc_conn" ]; then
			case "$assoc_conn" in
			*"WANPPPConnection"*)
				cmclient -v ppp_obj GETO "Device.PPP.Interface.*.[$PARAM_TR098=$assoc_conn]"
				[ ${#ppp_obj} -gt 0 ] && obj181="$ppp_obj.IPCP"
				;;
			*"WANIPConnection"*)
				cmclient -v ip_obj GETO "Device.IP.Interface.*.[$PARAM_TR098=$assoc_conn]"
				cmclient -v dhcp_obj GETO "Device.DHCPv4.Client.*.[Interface=$ip_obj]"
				[ ${#dhcp_obj} -gt 0 ] && obj181="$dhcp_obj"
				;;
			*) ;;

			esac
		fi
		;;
	esac
	eval $3='$obj181'
}
service_set_param() {
	local obj98="$1"
	local param98="$2"
	local _val="$3"
	case $param98 in
	"PassthroughMACAddress")
		if [ -z "$setm_params" ]; then
			_val="$(echo "$_val" | tr [A-F] [a-f])"
			setm_params="Device.X_ADB_DMZ.X_ADB_PassthroughMACAddress=$_val	Device.X_ADB_DMZ.X_ADB_AssociatedHost=\"\"	Device.X_ADB_DMZ.X_ADB_PassthroughUserDefined=false"
		else
			setm_params="$setm_params	Device.X_ADB_DMZ.X_ADB_PassthroughMACAddress=$_val	Device.X_ADB_DMZ.X_ADB_AssociatedHost=\"\"	Device.X_ADB_DMZ.X_ADB_PassthroughUserDefined=false"
		fi
		;;
	"UseAllocatedWAN")
		service_lookup_param "$obj" "$param98" obj181
		if [ "$_val" = "Passthrough" ]; then
			if [ -z "$setm_params" ]; then
				setm_params="$obj181.PassthroughDHCPPool=$found_obj	$obj181.PassthroughEnable=true"
			else
				setm_params="$setm_params	$obj181.PassthroughDHCPPool=$found_obj	$obj181.PassthroughEnable=true"
			fi
		else
			if [ -z "$setm_params" ]; then
				setm_params="$obj181.PassthroughEnable=false"
			else
				setm_params="$setm_params	$obj181.PassthroughEnable=false"
			fi
		fi
		;;
	*) ;;

	esac
}
service_get() {
	local obj98="$1" param98="$2" value98="" value181=""
	service_lookup_param "$obj98" "$param98" obj181
	case "$param98" in
	"UseAllocatedWAN")
		value98="Normal"
		if [ ${#obj181} -gt 0 ]; then
			cmclient -v value181 GETV "$obj181.PassthroughEnable"
			[ "$value181" = "true" ] && value98="Passthrough"
		fi
		;;
	"MACAddress")
		br_id="${obj98%.*}"
		br_id="${br_id##*.}"
		br_id=$((br_id - 1))
		read value98 </sys/class/net/"br$br_id"/address
		;;
	esac
	echo "$value98"
}
service_config() {
	setm_params=""
	for i in UseAllocatedWAN PassthroughMACAddress; do
		if eval [ \${set${i}:=0} -eq 1 ]; then
			eval service_set_param "$obj" "$i" \"\$new${i}\"
		fi
	done
	if [ -n "$setm_params" ]; then
		cmclient -u "tr098" SETM "$setm_params" >/dev/null
	fi
}
service_add() {
	tr181obj=$(help98_add_tr181obj "$obj.LANHostConfigManagement" "Device.DHCPv4.Server.Pool")
	cmclient SET "$obj.LANHostConfigManagement.$PARAM_TR181" "$tr181obj" >/dev/null
}
service_delete() {
	local found_obj=$(cmclient GETV "$obj.$PARAM_TR181")
	if [ -n "$found_obj" ]; then
		help181_del_object "$found_obj"
	fi
}
case "$op" in
"a")
	service_add
	;;
"d")
	service_delete
	;;
"s")
	cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
	[ ${#found_obj} -gt 0 ] && service_config
	;;
"g")
	cmclient -v found_obj GETV "$obj.X_ADB_TR181Name"
	if [ ${#found_obj} -gt 0 ]; then
		for arg; do # Arg list as separate words
			service_get "$obj" "$arg"
		done
	else
		for arg; do # Arg list as separate words
			echo ""
		done
	fi
	;;
esac
exit 0
