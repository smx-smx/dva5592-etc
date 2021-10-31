#!/bin/sh
PRIO_VALUE_835="1,1,1,1,1,5,1,1"
PRIO_VALUE_836="5,1,1,1,1,5,1,1"
FIX_PART_USRCHNG_FLG="/tmp/dlink_userchanged"
help_ppp_username_changed() {
	local lowlays="" setm="" prio_value="" vlanid="" clas=""
	local obj="$1" ppp_status="$2"
	if [ -f "$FIX_PART_USRCHNG_FLG$obj" -o "$ppp_status" != "Up" ]; then
		cmclient -v lowlays GETV "$obj.LowerLayers"
		IFS=","
		for lowlays in $lowlays; do
			case "$lowlays" in
			"Device.Ethernet.VLANTermination"*)
				cmclient -v vlanid GETV "$lowlays.VLANID"
				break
				;;
			esac
		done
		unset IFS
		case "$newUsername" in
		*"@megaoffice.it" | *"@megaoffice-ws.it")
			case "$vlanid" in
			"835")
				prio_value="$PRIO_VALUE_835"
				;;
			"836")
				prio_value="$PRIO_VALUE_836"
				;;
			*)
				prio_value="-1"
				;;
			esac
			;;
		*)
			prio_value="-1"
			;;
		esac
		cmclient SET Device.Ethernet.VLANTermination.[VLANID="$vlanid"].X_ADB_8021pPrio "$prio_value"
		[ -f "$FIX_PART_USRCHNG_FLG$obj" ] && rm -f "$FIX_PART_USRCHNG_FLG$obj"
	fi
}
help_check_custom_ppp_conditions() {
	local ppp_obj="$1"
	local low_layer="" im_obj="" wan_name="" action_ppp_reset="" onlineStatus="" action_value="" optical_name=""
	help_lowlayer_obj_get low_layer "$ppp_obj" "Device.Ethernet.Interface"
	cmclient -v optical_name GETV Device.Optical.Interface.1.Name
	cmclient -v wan_name GETV "$low_layer.Name"
	if [ "$wan_name" = "$optical_name" ]; then
		cmclient -v im_obj GETO Device.X_ADB_InterfaceMonitor.Group.Interface.[MonitoredInterface="$low_layer"]
		cmclient -v onlineStatus GETV "$im_obj.OnlineStatus"
		cmclient -v action_ppp_reset GETO "$im_obj.Action.[Path=$ppp_obj.Reset]"
		cmclient -v action_value GETV "$action_ppp_reset.Value"
		[ "$onlineStatus" = "Down" -a -n "$action_ppp_reset" -a "$action_value" = "true" ] && return 0
	fi
	return 1
}
help_get_hysteresisUp() {
	local intfObj="$2"
	[ "$1" = "hystUp" ] || local hystUp
	cmclient -v hystUp GETV "$intfObj.HysteresisUp"
	[ -z "$hystUp" -o "$hystUp" = "0" ] && hystUp="1"
	eval $1='$hystUp'
}
help_set_ppp_userchanged_flag() {
	local ppp_obj="$1" ppp_status=""
	cmclient -v ppp_status GETV "$ppp_obj".Status
	if [ "$ppp_status" = "Up" ]; then
		echo "1" >"$FIX_PART_USRCHNG_FLG$ppp_obj"
	else
		help_ppp_username_changed "$ppp_obj" "$ppp_status"
	fi
}
