#!/bin/sh
AH_NAME="TR098_Layer3Forwarding"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_set_param() {
	local _param="$1"
	local _val="$2"
	case $_param in
	"Interface")
		_val=$(cmclient GETO "Device.IP.Interface.*.[$PARAM_TR098=$_val]")
		cmclient SET "$found_obj.$_param" "$_val"
		;;
	esac
}
service_config() {
	if [ "${setInterface:=0}" -eq 1 ]; then
		service_set_param "Interface" "$newInterface"
	fi
}
service_add() {
	tr181obj=$(help98_add_tr181obj "$obj" "Device.Routing.Router.1.IPv4Forwarding")
	cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$tr181obj" >/dev/null
}
service_get() {
	local tr098obj="$1" param="$2" value="" tr181obj
	case $param in
	"DefaultConnectionService")
		cmclient -v tr181obj GETO Device.IP.Interface.[X_ADB_DefaultRoute="true"].[Status="Up"]
		for tr181obj in $tr181obj; do
			cmclient -v value GETV $tr181obj.X_ADB_TR098Reference
			[ -n "$value" ] && break
		done
		;;
	*) ;;

	esac
	echo "$value"
}
case "$op" in
a)
	service_add
	;;
d)
	found_obj=$(cmclient GETV "$obj.X_ADB_TR181Name")
	if [ -n "$found_obj" ]; then
		help181_del_object "$found_obj"
	fi
	;;
s)
	found_obj=$(cmclient GETV "$obj.X_ADB_TR181Name")
	if [ -n "$found_obj" ]; then
		service_config "$arg"
	fi
	;;
g)
	for arg; do
		service_get "$obj" "$arg"
	done
	;;
esac
exit 0
