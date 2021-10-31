#!/bin/sh
AH_NAME="TR098_ADD_BridgePort"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098() {
	local lowlayer=""
	local bridge_obj=""
	local tr98bridge=""
	local lan_intf=""
	local lan_device=""
	local changed_lan=""
	local lan_id=""
	local portId=""
	lowlayer="$newLowerLayers"
	bridge_obj="${obj%.Port*}"
	tr98bridge=$(cmclient GETV "$bridge_obj.$PARAM_TR098")
	if [ -n "$tr98bridge" ] && [ -n "$lowlayer" ]; then
		case "$lowlayer" in
		*"Bridging.Bridge"*)
			cmclient -u "BridgingBridge$obj" SET "$obj.$PARAM_TR098" "$tr98bridge" >/dev/null
			;;
		*)
			lan_intf=$(cmclient GETV "$lowlayer.$PARAM_TR098")
			case "$lan_intf" in
			*"LANDevice"* | *"LANInterfaces"*)
				lan_device=$(help98_bridge_landevice "$tr98bridge" "$bridge_obj")
				if [ -n "$lan_device" ]; then
					changed_lan=$(help_strstr "$lan_intf" "$lan_device")
				fi
				if [ -z "$changed_lan" -o -z "$lan_device" ]; then
					help98_del_bridge_availablelist "$lan_intf"
					help181_del_tr98obj "$lan_intf"
					if [ -z "$lan_device" ]; then
						cmclient -v lan_id ADD "$OBJ_IGD.LANDevice"
						lan_device="$OBJ_IGD.LANDevice.$lan_id."
					fi
					case "$lan_intf" in
					*"LANEthernetInterfaceConfig"*)
						help98_add_xan_xconfig "$lan_device""LANEthernetInterfaceConfig" "$lowlayer" "EthernetIf$lowlayer"
						;;
					*"WLANConfiguration"*)
						help98_add_xan_xconfig "$lan_device""WLANConfiguration" "$lowlayer" "WiFiSSID$lowlayer"
						;;
					esac
				fi
				;;
			*"WANEthernetInterfaceConfig"*)
				help98_add_bridge_availablelist "$lan_intf" "WANInterface"
				;;
			*"WANConnectionDevice"*)
				help98_add_bridge_availablelist "${lan_intf%.*}" "WANInterface"
				;;
			esac
			portId=$(help181_add_tr98obj "$tr98bridge.Port" "$obj")
			cmclient -u "BridgingBridge$obj" SET "$obj.$PARAM_TR098" "$tr98bridge.Port.$portId" >/dev/null
			;;
		esac
	fi
}
service_delete_tr098() {
	local lowlayer=""
	local tr98ref=""
	local tr98lower_if=""
	local tmpObj=""
	local lanDeviceObj=""
	lowlayer="$newLowerLayers"
	case "$lowlayer" in
	*"Bridging.Bridge"*)
		return
		;;
	*)
		tr98ref="$newX_ADB_TR098Reference"
		if [ -n "$tr98ref" ]; then
			help181_del_tr98obj "$tr98ref"
		fi
		tr98lower_if=$(cmclient GETV "$lowlayer.$PARAM_TR098")
		case "$tr98lower_if" in
		*"LANDevice"*)
			if [ -n "$tr98lower_if" ]; then
				help98_del_bridge_availablelist "$tr98lower_if"
				help181_del_tr98obj "$tr98lower_if"
			fi
			if [ "$user" != "NoWiFi" ]; then
				case "$tr98lower_if" in
				*"LANEthernetInterfaceConfig"*)
					help98_add_lan_default "$lowlayer" "LANEthernetInterfaceConfig" "EthernetIf"
					;;
				*"WLANConfiguration"*)
					help98_add_lan_default "$lowlayer" "WLANConfiguration" "WiFiSSID"
					;;
				esac
			fi
			tmpObj="${tr98lower_if#*[0-9]*.}"
			lanDeviceObj="${tr98lower_if%%.$tmpObj}"
			if [ -n "$lanDeviceObj" ]; then
				help98_delete_lanDevice "$lanDeviceObj"
			fi
			;;
		esac
		;;
	esac
}
case "$op" in
"s")
	service_align_tr098
	;;
"d")
	service_delete_tr098
	;;
esac
exit 0
