#!/bin/sh
AH_NAME="TR098_WANPTMLinkConfig"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_set_param() {
	local _obj="$1"
	local _param="$2"
	local _val="$3"
	case $_param in
	"X_ADB_VLANID")
		vlan_obj=$(cmclient GETO "Device.Ethernet.VLANTermination.*.[X_ADB_TR098Reference=$_obj]")
		if [ -z "$vlan_obj" ]; then
			eth_link=$(help98_add_tr181obj "$_obj" "Device.Ethernet.Link")
			help181_set_param "$eth_link.LowerLayers" "$tr181obj"
			help181_set_param "$eth_link.Enable" "true"
			vlan_obj=$(help98_add_tr181obj "$_obj" "Device.Ethernet.VLANTermination")
			help181_set_param "$vlan_obj.LowerLayers" "$eth_link"
		fi
		help181_set_param "$vlan_obj.VLANID" "$_val"
		;;
	esac
}
service_config() {
	for i in X_ADB_VLANID; do
		if eval [ \${set${i}:=0} -eq 1 ]; then
			eval service_set_param "$obj" "$i" \"\$new${i}\"
		fi
	done
}
service_add() {
	local tr181obj wan_path
	wan_path=${obj%.*}
	wan_path=${wan_path%.*}
	wan_path=${wan_path%.*}
	cmclient -v tr181obj GETO Device.PTM.Link."[LowerLayers=%($wan_path.WANDSLInterfaceConfig.X_ADB_TR181_CHAN)]"
	if [ ${#tr181obj} -eq 0 ]; then
		tr181obj=$(help98_add_tr181obj "$obj" "Device.PTM.Link")
		help98_link_tr181obj "${obj%%.WANConnectionDevice*}.WANDSLInterfaceConfig" "$tr181obj" "Device.DSL.Channel"
	fi
	cmclient -u "$AH_NAME" SET "$obj.$PARAM_TR181" "$tr181obj" >/dev/null
}
service_delete() {
	local tr181objReferences wan_path
	wan_path=${obj%.*}
	wan_path=${wan_path%.*}
	vlan_obj=$(cmclient GETO "Device.Ethernet.VLANTermination.*.[X_ADB_TR098Reference=$obj]")
	if [ -n "$vlan_obj" ]; then
		eth_link=$(cmclient GETV "$vlan_obj.LowerLayers")
		help181_del_object "$vlan_obj"
		if [ -n "$eth_link" ]; then
			help181_del_object "$eth_link"
		fi
	fi
	help98_del_bridge_availablelist "${obj%.WANPTMLinkConfig*}"
	cmclient -v tr181objReferences GETO "$wan_path.WANPTMLinkConfig.[X_ADB_TR181Name=$tr181obj]"
	if [ "$obj" = "$tr181objReferences" ]; then
		help181_del_object "$tr181obj"
	fi
}
case "$op" in
d)
	tr181obj=$(cmclient GETV "$obj.X_ADB_TR181Name")
	if [ -n "$tr181obj" ]; then
		service_delete
	fi
	;;
a)
	service_add
	;;
s)
	tr181obj=$(cmclient GETV "$obj.X_ADB_TR181Name")
	if [ -n "$tr181obj" ]; then
		service_config
	fi
	;;
esac
exit 0
