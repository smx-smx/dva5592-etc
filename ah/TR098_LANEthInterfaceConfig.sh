#!/bin/sh
AH_NAME="LANEthernetInterfaceConfig"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_set_param() {
	local _param="$1"
	local _val="$2"
	case "$_param" in
	"MaxBitRate")
		if [ "$_val" = "Auto" ]; then
			_val="-1"
		fi
		;;
	esac
	cmclient SET "$tr181obj.$_param" "$_val" >/dev/null
}
service_lookup_value() {
	local _tr181param="$1" _tr181val="$2" _tr098val="$2"
	case "$_tr181param" in
	"MaxBitRate")
		[ "$_tr181val" = "-1" ] && _tr098val="Auto"
		;;
	"Status")
		help98_get_ifstatus _tr098val "$_tr181val"
		;;
	*)
		_tr098val=""
		;;
	esac
	echo "$_tr098val"
}
service_get() {
	local obj98="$1" param98="$2"
	param181="$param98"
	case $param181 in
	"MaxBitRate" | "Status")
		cmclient -v paramval GETV "$tr181obj.$param181"
		;;
	esac
	service_lookup_value "$param181" "$paramval"
}
service_config() {
	if [ "${setMaxBitRate:=0}" -eq 1 ]; then
		service_set_param "MaxBitRate" "$newMaxBitRate"
	fi
}
service_add() {
	obj_found=0
	for tr181obj in $(cmclient GETO "Device.Ethernet.Interface.[$PARAM_TR098=]"); do
		cmclient SET "$tr181obj.$PARAM_TR098" "$obj" >/dev/null
		help181_set_param "$tr181obj.Upstream" "false" >/dev/null
		obj_found=1
		break
	done
	if [ "$obj_found" -ne 1 ]; then
		tr181obj=$(help98_add_tr181obj "$obj" "Device.Ethernet.Interface")
	fi
	cmclient SET "$obj.$PARAM_TR181" "$tr181obj" >/dev/null
	help98_add_bridge_availablelist "$obj" "LANInterface"
}
service_delete() {
	cmclient SET "$tr181obj.$PARAM_TR098" "" >/dev/null
	help98_del_bridge_availablelist "$obj"
}
case "$op" in
a)
	service_add
	;;
d)
	cmclient -v tr181obj GETV "$obj.X_ADB_TR181Name"
	[ -n "$tr181obj" ] && service_delete
	;;
g)
	cmclient -v tr181obj GETV "$obj.X_ADB_TR181Name"
	if [ ${#tr181obj} -gt 0 ]; then
		for arg; do # Arg list as separate words
			service_get "$obj" "$arg"
		done
	else
		for arg; do # Arg list as separate words
			echo ""
		done
	fi
	;;
s)
	cmclient -v tr181obj GETV "$obj.X_ADB_TR181Name"
	[ -n "$tr181obj" ] && service_config
	;;
esac
exit 0
