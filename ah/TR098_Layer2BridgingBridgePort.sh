#!/bin/sh
AH_NAME="TR098_Layer2BridgingBridgePort"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_link_stack() {
	local _tr098obj="$1"
	local _tr181obj="$2"
	local _tr098int="$3"
	lowerlayer98=$(cmclient GETV "InternetGatewayDevice.Layer2Bridging.AvailableInterface.*.[AvailableInterfaceKey=$_tr098int].InterfaceReference")
	case "$lowerlayer98" in
	*"WLANConfiguration"*)
		lowerlayer181=$(cmclient GETV "$lowerlayer98.X_ADB_TR181_SSID")
		;;
	*"WANConnectionDevice"*)
		lowerlayer181=$(cmclient GETV "$lowerlayer98.WANDSLLinkConfig.$PARAM_TR181")
		if [ -z "$lowerlayer181" ]; then
			lowerlayer181=$(cmclient GETV "$lowerlayer98.WANEthernetLinkConfig.$PARAM_TR181")
			if [ -z "$lowerlayer181" ]; then
				lowerlayer181=$(cmclient GETV "$lowerlayer98.WANPTMLinkConfig.$PARAM_TR181")
			fi
		fi
		;;
	*)
		lowerlayer181=$(cmclient GETV "$lowerlayer98.$PARAM_TR181")
		;;
	esac
	if [ -n "$lowerlayer181" ]; then
		help181_set_param "$_tr181obj.LowerLayers" "$lowerlayer181"
	fi
}
service_config() {
	if [ "${setPortInterface:=0}" -eq 1 ]; then
		service_link_stack "obj" "$found_obj" "$newPortInterface"
	fi
}
service_add() {
	br_obj="${obj%.Port*}"
	br181_obj=$(cmclient GETV "$br_obj.X_ADB_TR181Name")
	if [ -n "$br181_obj" ]; then
		br181_port=$(help98_add_tr181obj "$obj" "$br181_obj.Port")
		cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$br181_port" >/dev/null
	fi
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
		service_config
	fi
	;;
esac
exit 0
