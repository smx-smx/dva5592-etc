#!/bin/sh
AH_NAME="RTSPProxy"
[ "$user" = "${AH_NAME}" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_ipcalc.sh
. /etc/ah/helper_svc.sh
flush_rtsp_rules() {
	help_iptables -t nat -F RtspRedirect
	help_iptables -t filter -F RtspOut
	help_iptables -t filter -F RtspIn
}
add_wlan_to_lan_filtering() {
	local _br_name="$1" _tmp _ipif _wif _wif_name _net _mask _br="Device.Bridging.Bridge.Port" oldifs="$IFS"
	if [ ${#_br_name} -ne 0 ]; then
		cmclient -v _br GETO "$_br.[ManagementPort=true].[Name=$1]"
		[ ${#_br} -eq 0 ] && return
		_br=${_br%.*}
	fi
	unset IFS
	cmclient -v _wif GETO Device.WiFi.SSID
	for _wif in $_wif; do
		cmclient -v _tmp GETO "$_br.[ManagementPort=false].[LowerLayers=$_wif]"
		[ ${#_tmp} -eq 0 ] && continue
		[ ${#1} -eq 0 ] && cmclient -v _br_name GETV "${_tmp%.*}.[ManagementPort=true].Name"
		cmclient -v _wif_name GETV "$_wif.Name"
		help_ip_interface_get _ipif "$_tmp"
		cmclient -v _ipif GETO "$_ipif.IPv4Address.[Enable=true]"
		for _ipif in $_ipif; do
			cmclient -v _tmp GETV "$_ipif.IPAddress"
			cmclient -v _mask GETV "$_ipif.SubnetMask"
			help_calc_network _net "$_tmp" "$_mask"
			help_iptables -t nat -I RtspRedirect -i "$_br_name" -m physdev --physdev-in "$_wif_name" \
				-p tcp -d "$_net/$_mask" --dport "$2" -j RETURN
		done
	done
	IFS="$oldifs"
}
IFS=","
if [ "$setEnable" = "1" -o "$changedPorts" = "1" -o "$changedDebug" = "1" -o "$changedDownstreamInterfaces" = "1" ]; then
	[ "$oldStatus" = "Enabled" ] && flush_rtsp_rules
	firstport=""
	if [ "$newEnable" = "true" ]; then
		intfs=""
		for intf in $newDownstreamInterfaces; do
			help_lowlayer_ifname_get llintf "$intf"
			intfs="${intfs:+$intfs,}$llintf"
		done
		for port in $newPorts; do
			if [ -z "$firstport" ]; then
				firstport="$port"
				debugflag=""
				[ "$newDebug" = "true" ] && debugflag="-d"
				help_svc_start "rtspproxy -p $firstport $debugflag $marking" "rtspproxy"
			fi
			if [ -z "$newDownstreamInterfaces" ]; then
				help_iptables -t nat -I RtspRedirect -p tcp --dport "$port" -j REDIRECT --to-ports "$firstport"
				add_wlan_to_lan_filtering "" "$port"
				help_iptables -t filter -I RtspIn -p tcp --dport "$port" -j ACCEPT
			else
				for intf in $intfs; do
					help_iptables -t nat -I RtspRedirect -i "$intf" -p tcp --dport "$port" -j REDIRECT --to-ports "$firstport"
					add_wlan_to_lan_filtering "$intf" "$port"
					help_iptables -t filter -I RtspIn -i "$intf" -p tcp --dport "$port" -j ACCEPT
				done
				help_iptables -t filter -I RtspOut -p tcp --dport "$port" -j ACCEPT
			fi
		done
		cmclient SETE "Device.Services.X_ADB_RTSPProxy.Status" Enabled
	else
		help_svc_stop "rtspproxy"
		cmclient SETE "Device.Services.X_ADB_RTSPProxy.Status" Disabled
	fi
fi
unset IFS
exit 0
