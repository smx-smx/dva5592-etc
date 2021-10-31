#!/bin/sh
AH_NAME="TR098_ADD_PPP"
[ "$user" = "tr098" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_align_tr098() {
	local lowlayer=""
	local tr98lowlayer=""
	local set_lowlayer=""
	local lowlayer2=""
	local lowlayer3=""
	local l3obj=""
	local vlanobj=""
	local tr098ref=""
	local wanConnDevice=""
	local wanIpConn_inst=""
	local set_m=""
	lowlayer="$newX_ADB_ActiveLowerLayer"
	cmclient -v tr98lowlayer GETV "$lowlayer.$PARAM_TR098"
	if [ -z "$tr98lowlayer" ]; then
		set_lowlayer="1"
		cmclient -v lowlayer2 GETV "$lowlayer.LowerLayers"
		cmclient -v tr98lowlayer GETV "$lowlayer2.$PARAM_TR098"
	fi
	vlanobj=${lowlayer%.*}
	if [ "$vlanobj" = "Device.Ethernet.VLANTermination" ]; then
		cmclient -v lowlayer2 GETV "$lowlayer.LowerLayers"
		cmclient -v lowlayer3 GETV "$lowlayer2.LowerLayers"
		l3obj=${lowlayer3%.*}
		[ "$l3obj" = "Device.Ethernet.Interface" ] && cmclient -v tr098ref GETV "$lowlayer2.$PARAM_TR098" || cmclient -v tr098ref GETV "$lowlayer3.$PARAM_TR098"
		set_m="$lowlayer.$PARAM_TR098=$tr098ref"
		wanConnDevice="${tr098ref%.*}"
		wanIpConn_inst=$(help181_add_tr98obj "$wanConnDevice.WANPPPConnection" "$obj")
		set_m="$set_m	$obj.$PARAM_TR098=$wanConnDevice.WANPPPConnection.$wanIpConn_inst"
		cmclient SETEM "$set_m" >/dev/null
	elif [ "$vlanobj" = "Device.X_ADB_MobileModem.Interface" ]; then
		local wanDevice="${tr98lowlayer%.*}" TR181Name="" wanppp_obj=""
		cmclient -v wanppp_obj GETO "$wanDevice.WANConnectionDevice"
		if [ -n "$wanppp_obj" ]; then
			cmclient -v TR181Name GETV "$wanppp_obj.X_ADB_TR181Name"
			[ -n "$TR181Name" -a "$TR181Name" != "$obj" ] && wanppp_obj=""
		fi
		if [ -z "$wanppp_obj" ]; then
			conn_id=$(help181_add_tr98obj "$wanDevice.WANConnectionDevice")
			wanppp_obj="$wanDevice.WANConnectionDevice.$conn_id.WANPPPConnection"
		else
			wanppp_obj="$wanppp_obj.WANPPPConnection"
		fi
		pppId=$(help181_add_tr98obj "$wanppp_obj" "$obj")
		cmclient -u "PPPIf$obj" SETE "$obj.$PARAM_TR098" "$wanppp_obj.$pppId"
	elif [ -n "$tr98lowlayer" ]; then
		wanConnDevice="${tr98lowlayer%.*}"
		wanIpConn_inst=$(help181_add_tr98obj "$wanConnDevice.WANPPPConnection" "$obj")
		cmclient SETE "$obj.$PARAM_TR098" "$wanConnDevice.WANPPPConnection.$wanIpConn_inst"
		[ "$set_lowlayer" = "1" ] && cmclient SETE "$lowlayer.$PARAM_TR098" "$tr98lowlayer"
	fi
}
service_delete_tr098() {
	local tr98ref=""
	tr98ref="$newX_ADB_TR098Reference"
	if [ -n "$tr98ref" ]; then
		help181_del_tr98obj "$tr98ref"
	fi
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
