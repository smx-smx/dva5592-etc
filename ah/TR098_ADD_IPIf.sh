#!/bin/sh
AH_NAME="TR098_ADD_IPIf"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
helper_add_portmap() {
	local _obj="$1"
	local _tr098obj="$2"
	for port_map in $(cmclient GETO "Device.NAT.PortMapping.*.[Interface=$_obj]"); do
		portId=$(help181_add_tr98obj "$_tr098obj.PortMapping" "$port_map")
		cmclient SETE "$port_map.$PARAM_TR098" "$_tr098obj.PortMapping.$portId"
	done
}
service_align_tr098() {
	local lowlayer=""
	local lowlayer2=""
	local tr98lowlayer=""
	local tr098ref=""
	local wanConnDevice=""
	local wanIpConn_inst=""
	local bridgeObj=""
	local portIf=""
	local bridgeIf=""
	local tmpObj=""
	local lanObj=""
	lowlayer="$newX_ADB_ActiveLowerLayer"
	cmclient -v tr98lowlayer GETV "$lowlayer.$PARAM_TR098"
	case "$lowlayer" in
	*"VLANTermination"*)
		cmclient -v lowlayer2 GETV "$lowlayer.LowerLayers"
		cmclient -v tr098ref GETV "$lowlayer2.X_ADB_TR098Reference"
		cmclient SETE "$lowlayer.X_ADB_TR098Reference" "$tr098ref"
		wanConnDevice="${tr098ref%.*}"
		wanIpConn_inst=$(help181_add_tr98obj "$wanConnDevice.WANIPConnection" "$obj")
		cmclient SETE "$obj.$PARAM_TR098" "$wanConnDevice.WANIPConnection.$wanIpConn_inst"
		helper_add_portmap "$obj" "$wanConnDevice.WANIPConnection.$wanIpConn_inst"
		;;
	*"PPP.Interface"*)
		cmclient SETE "$obj.$PARAM_TR098" "$tr98lowlayer"
		cmclient SETE "$tr98lowlayer.X_ADB_TR181_IPName" "$obj"
		helper_add_portmap "$obj" "$tr98lowlayer"
		;;
	*)
		if [ -z "$tr98lowlayer" ]; then
			set_lowlayer="1"
			lowlayer2=$(cmclient GETV "$lowlayer.LowerLayers")
			tr98lowlayer=$(cmclient GETV "$lowlayer2.$PARAM_TR098")
		fi
		case "$tr98lowlayer" in
		*"Layer2Bridging"*)
			bridgeObj="${tr98lowlayer%.Port*}"
			for portIf in $(help98_get_param "$bridgeObj.Port.*.PortInterface"); do
				bridgeIf=$(help98_get_param "InternetGatewayDevice.Layer2Bridging.AvailableInterface.*.[AvailableInterfaceKey=$portIf].InterfaceReference")
				if [ -n "$bridgeIf" ]; then
					break
				fi
			done
			if [ -n "$bridgeIf" ]; then
				tmpObj="${bridgeIf##*[0-9].}"
				lanObj="${bridgeIf%%.$tmpObj}"
				case "$lanObj" in
				*"LANDevice"*)
					cmclient SETE "$obj.$PARAM_TR098" "$lanObj.LANHostConfigManagement"
					if [ "$set_lowlayer" = "1" ]; then
						cmclient SETE "$lowlayer.$PARAM_TR098" "$lanObj.LANHostConfigManagement"
					fi
					;;
				esac
			fi
			;;
		*"LANDevice"*)
			tmpObj="${tr98lowlayer#*[0-9]*.}"
			lanObj="${tr98lowlayer%%.$tmpObj}"
			cmclient SETE "$obj.$PARAM_TR098" "$lanObj.LANHostConfigManagement"
			if [ "$set_lowlayer" = "1" ]; then
				cmclient SETE "$lowlayer.$PARAM_TR098" "$lanObj.LANHostConfigManagement"
			fi
			;;
		*"WANDevice"*)
			wanConnDevice="${tr98lowlayer%.*}"
			wanIpConn_inst=$(help181_add_tr98obj "$wanConnDevice.WANIPConnection" "$obj")
			cmclient SETE "$obj.$PARAM_TR098" "$wanConnDevice.WANIPConnection.$wanIpConn_inst"
			if [ "$set_lowlayer" = "1" ]; then
				cmclient SETE "$lowlayer.$PARAM_TR098" "$tr98lowlayer"
			fi
			helper_add_portmap "$obj" "$wanConnDevice.WANIPConnection.$wanIpConn_inst"
			;;
		*) ;;

		esac
		;;
	esac
}
service_delete_tr098() {
	local tr98ref=""
	tr98ref="$newX_ADB_TR098Reference"
	case "$tr98ref" in
	*"LANHostConfigManagement"*)
		return
		;;
	*)
		if [ -n "$tr98ref" ]; then
			help181_del_tr98obj "$tr98ref"
		fi
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
