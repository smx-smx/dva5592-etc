#!/bin/sh
AH_NAME="TR098_ADD_EthernetIf"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098() {
	local upstream_new=""
	local upstream_old=""
	local tr98obj=""
	local wanDevice_inst=""
	local wanEthIf_inst=""
	local wanDevice_obj=""
	upstream_new="$newUpstream"
	upstream_old="$oldUpstream"
	if [ "$upstream_new" = "$upstream_old" ]; then
		return
	fi
	tr98obj=$(cmclient GETV "$obj.$PARAM_TR098")
	if [ -n "$tr98obj" ]; then
		help181_del_tr98obj "$tr98obj"
		help98_del_bridge_availablelist "$tr98obj"
	fi
	if [ "$upstream_new" = "true" ]; then
		wanDevice_inst=$(help181_add_tr98obj "InternetGatewayDevice.WANDevice")
		wanEthIf_inst=$(help181_add_tr98obj "InternetGatewayDevice.WANDevice.$wanDevice_inst.WANEthernetInterfaceConfig" "$obj")
		cmclient -u "EthernetIf$obj" SET "$obj.$PARAM_TR098" "InternetGatewayDevice.WANDevice.$wanDevice_inst.WANEthernetInterfaceConfig" >/dev/null
	else
		if [ -n "$tr98obj" ]; then
			wanDevice_obj="${tr98obj%.WANEthernetInterfaceConfig*}"
			if [ -n "$wanDevice_obj" ]; then
				help181_del_tr98obj "$wanDevice_obj"
			fi
		fi
		help98_add_lan_default "$obj" "LANEthernetInterfaceConfig" "EthernetIf"
	fi
}
service_delete_tr098() {
	local tr98ref=""
	local wanDevice_obj=""
	tr98ref=$(cmclient GETV "$obj.$PARAM_TR098")
	case "$tr98ref" in
	*"WANEthernetInterfaceConfig"*)
		help181_del_tr98obj "$tr98ref"
		wanDevice_obj="${tr98ref%.WANEthernetInterfaceConfig*}"
		if [ -n "$wanDevice_obj" ]; then
			help181_del_tr98obj "$wanDevice_obj"
		fi
		;;
	*"LANEthernetInterfaceConfig"*)
		help98_del_bridge_availablelist "$tr98ref"
		help181_del_tr98obj "$tr98ref"
		;;
	*) ;;

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
