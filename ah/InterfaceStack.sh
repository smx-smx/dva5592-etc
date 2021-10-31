#!/bin/sh
AH_NAME="InterfaceStack"
[ "$user" = "InterfaceStack" ] && exit 0
get_active_ll() {
	local lowers=$2 lower active="" st
	if [ "$lowers" != "${2%%,*}" ]; then
		[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
		IFS=','
		for lower in $lowers; do
			cmclient -v st GETV "$lower.Status"
			[ "$st" != "Up" ] && continue
			active=$lower
			break
		done
		[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
	else
		active=$lowers
	fi
	eval $1='$active'
}
check_active_change() {
	local upper="$1" lowers="$2" ll ref
	case $upper in
	Device.Ethernet.VLANTermination.* | Device.Ethernet.Link.* | Device.PPP.Interface.* | Device.IP.Interface.*)
		[ ${#lowers} -eq 0 ] && cmclient -v lowers GETV "$upper.LowerLayers"
		get_active_ll ll "$lowers"
		[ -n "$ll" ] && cmclient $3 "$upper.X_ADB_ActiveLowerLayer" "$ll"
		[ -d /etc/cm/tr098/ ] || return
		case $upper in
		Device.IP.Interface.* | Device.PPP.Interface.*)
			[ "$3" = "SETE" -a -n "$ll" ] && cmclient -u USER_SKIP_EXEC SET "$upper.X_ADB_ActiveLowerLayer" "$ll"
			;;
		esac
		;;
	esac
}
add_stack() {
	local obj=$1 lowers=$2 lower
	[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
	IFS=','
	for lower in $lowers; do
		cmclient -v id ADD InterfaceStack
		[ ${#set_arg} -gt 0 ] && set_arg="$set_arg	"
		set_arg=$set_arg"InterfaceStack.$id.HigherLayer=$obj	InterfaceStack.$id.LowerLayer=$lower"
	done
	[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
}
service_delete() {
	cmclient DEL "InterfaceStack.[LowerLayer=$obj]"
	cmclient DEL "InterfaceStack.[HigherLayer=$obj]"
}
service_config() {
	local objs lower higher wwwan_query=""
	if [ "$changedLowerLayers" = "1" ]; then
		[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
		IFS=','
		for lower in $oldLowerLayers; do
			cmclient DEL "InterfaceStack.[LowerLayer=$lower].[HigherLayer=$obj]"
		done
		[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
		set_arg=""
		add_stack $obj "$newLowerLayers"
		cmclient SETM "$set_arg"
		check_active_change $obj "$newLowerLayers" "-a SET"
	fi
	if [ "$changedStatus" = "1" ]; then
		cmclient -v objs GETV "Device.InterfaceStack.[LowerLayer=$obj].HigherLayer"
		for higher in $objs; do
			check_active_change $higher "" SETE
			case "$obj" in
			*"X_ADB_MobileModem.Interface"* | *"USB.Interface"*)
				wwwan_query="[Status!NotPresent]."
				;;
			esac
			cmclient -a -u InterfaceStack SET "$higher.[Enable=true].${wwwan_query}Enable" true
		done
	fi
}
if [ "$1" = "init" ]; then
	cmclient -v ll GET Device.**.LowerLayers
	set_arg=""
	for line in $ll; do
		obj=${line%%.LowerLayers;*}
		lls=${line#*;}
		add_stack $obj $lls
	done
	cmclient SETM "$set_arg"
fi
case "$op" in
s)
	service_config
	;;
d)
	service_delete
	;;
esac
exit 0
