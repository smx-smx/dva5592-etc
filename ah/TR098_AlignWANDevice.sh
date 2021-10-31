#!/bin/sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
. /etc/ah/TR098_AlignAll.sh
SET_ATTRIBUTES_SH="/tmp/cfg/attribute_set.sh"
WANDEVICE_ATTRIBUTES_ALIGN="/tmp/WANDeviceAlignAttribute.sh"
profile="$1"
reconf_profile() {
	local _wan="$1"
	local _mode="$2"
	remove_reference
	for cmd in $(cmclient GETA InternetGatewayDevice.WANDevice. | grep -v ";0"); do
		echo "cmclient SETA $(echo $cmd | sed 'y/;/ /')" >>"$WANDEVICE_ATTRIBUTES_ALIGN"
	done
	case "$_wan" in
	"dsl")
		for dsl in $(cmclient GETO "Device.DSL.Line"); do
			for wan_dev in $(cmclient GETO "InternetGatewayDevice.WANDevice.*.WANDSLInterfaceConfig.[X_ADB_TR181Name=$dsl]"); do
				wan_id="${wan_dev##*WANDevice.}"
				wan_id="${wan_id%%.*}"
				help98_destroy_wanconnection "$wan_id"
			done
			for chan in $(cmclient GETO "Device.DSL.Channel.*.[LowerLayers=$dsl]"); do
				cmclient -u "DslChannel$chan" SET "$chan.$PARAM_TR098" "$OBJ_IGD.WANDevice.$wan_id.WANDSLInterfaceConfig"
				help98_build_wanconnection "$wan_id" "$chan" "$_mode"
			done
		done
		;;
	"eth")
		for eth_intf in $(cmclient GETO "Device.Ethernet.Interface.*.[Upstream=true]"); do
			for wan_dev in $(cmclient GETO "InternetGatewayDevice.WANDevice.*.WANEthernetInterfaceConfig.[X_ADB_TR181Name=$eth_intf]"); do
				wan_id="${wan_dev##*WANDevice.}"
				wan_id="${wan_id%%.*}"
				help98_destroy_wanconnection "$wan_id"
			done
			for ip_int in $(cmclient GETO Device.IP.Interface.[Alias="$profile"]); do
				conn_id=$(help181_add_tr98obj "$OBJ_IGD.WANDevice.$wan_id.WANConnectionDevice")
				eth_link=$(cmclient GETV "$ip_int".LowerLayers)
				help98_add_xan_xconfig "$OBJ_IGD.WANDevice.$wan_id.WANConnectionDevice.$conn_id.WANEthernetLinkConfig" "$eth_link" "EthernetLink$eth_link"
				help98_build_wan_ip_ppp "$eth_link" "$OBJ_IGD.WANDevice.$wan_id.WANConnectionDevice.$conn_id" "EthernetLink" "WANEthernetLinkConfig"
			done
		done
		;;
	esac
	if [ -f "$WANDEVICE_ATTRIBUTES_ALIGN" ]; then
		. "$WANDEVICE_ATTRIBUTES_ALIGN" >/dev/null
		cmclient SAVE >/dev/null
		rm "$WANDEVICE_ATTRIBUTES_ALIGN" >/dev/null
	fi
}
remove_reference() {
	cmclient SET "Device.IP.Interface.[X_ADB_Upstream=true].X_ADB_TR098Reference" ""
}
ip_int=$(cmclient GETO Device.IP.Interface.[Alias="$profile"])
[ -z "$ip_int" ] && exit 0
echo "Profile: **$profile**"
case "$profile" in
"PTM" | "PPPoE - VDSL")
	wan="dsl"
	mode="ptm"
	;;
"PPP_ETHoA" | "ETHoA")
	wan="dsl"
	mode="atm"
	;;
"FIBER" | "TAGGED_FIBER" | "PPP - TaggedFiber")
	wan="eth"
	;;
*)
	exit 0
	;;
esac
reconf_profile "$wan" "$mode"
if [ -f "$SET_ATTRIBUTES_SH" ]; then
	/bin/sh "$SET_ATTRIBUTES_SH" >/dev/null
	rm "$SET_ATTRIBUTES_SH" >/dev/null
fi
exit 0
