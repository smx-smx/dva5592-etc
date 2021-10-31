#!/bin/sh
AH_NAME="PPPoEProxy"
[ "$user" = "${AH_NAME}" ] && exit 0
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_functions.sh
getBridge() {
	local _iff=$1 _ret=$2 _obj=""
	cmclient -v _obj GETO "Device.Bridging.Bridge.1.+.[LowerLayers=$_iff]"
	if [ ${#_obj} -ne 0 ]; then
		_obj=${_obj%%??}
		cmclient -v _iff GETV "$_obj.[ManagementPort=true].Name"
		eval $_ret=\$_iff
	else
		eval $_ret=""
	fi
}
configure_outbound() {
	local _outbound="$1" _iff="" _obj=""
	IFS=","
	for _obj in $_outbound; do
		if [ ${_obj%.*} = "Device.IP.Interface" ]; then
			help_active_lowlayer _obj "$_obj"
			[ ${_obj%.*} = "Device.PPP.Interface" ] && help_active_lowlayer _obj "$_obj"
		fi
		help_lowlayer_ifname_get _iff "$_obj"
		[ ${#_iff} -ne 0 ] && outifBuf="$outifBuf -S $_iff"
	done
	unset IFS
}
configure_inbound() {
	local _inbound="$1" _iff="" _ifName="" _ifBr=""
	IFS=","
	for _iff in $_inbound; do
		getBridge $_iff '_ifBr'
		if [ ${#_ifBr} -ne 0 ]; then
			[ "$inifBuf" = "${inifBuf#*$_ifBr}" ] && inifBuf="$inifBuf -C $_ifBr"
		else
			help_lowlayer_ifname_get _ifName "$_iff"
			[ -n "$_ifName" -a "$inifBuf" = "${inifBuf#*$_ifName}" ] && inifBuf="$inifBuf -C $_ifName"
		fi
	done
	unset IFS
}
stop_pppoer() {
	if pgrep pppoe-relay >/dev/null; then
		killall pppoe-relay
		cmclient SETE "Device.Services.X_ADB_PPPoEProxy.Status" Disabled
	fi
	ebtables -t nat -D PREROUTING --logical-in pr+ -j ACCEPT
}
start_pppoer() {
	local maxs mem_total pt
	if [ ${#outifBuf} -ne 0 -a ${#inifBuf} -ne 0 ]; then
		read -r _ mem_total _ </proc/meminfo
		[ $mem_total -lt 32000 ] && maxs="-n 100"
		if pppoe-relay -D $pt $maxs $outifBuf $inifBuf; then
			cmclient SETE "Device.Services.X_ADB_PPPoEProxy.Status" Enabled
			ebtables -t nat -I PREROUTING --logical-in pr+ -j ACCEPT
		else
			cmclient SETE "Device.Services.X_ADB_PPPoEProxy.Status" Error
		fi
	else
		cmclient SETE "Device.Services.X_ADB_PPPoEProxy.Status" Error
	fi
}
reset_stats() {
	local _obj cli_name cli_sid
	cmclient -v _obj GETO Device.Services.X_ADB_PPPoEProxy.Client
	for _obj in $_obj; do
		cmclient -v cli_name GETV "%($_obj.ClientInterface).Name"
		cmclient -v cli_sid GETV "$_obj.ClientSessionId"
		echo "${cli_name}_$cli_sid" >/proc/net/reset_stats
	done
}
service_config() {
	. /etc/ah/helper_serialize.sh && help_serialize $AH_NAME
	case $obj in
	Device.ATM.Link.*)
		local enable outbound inbound
		cmclient -v enable GETV "Device.Services.X_ADB_PPPoEProxy.Enable"
		cmclient -v outbound GETV "Device.Services.X_ADB_PPPoEProxy.OutboundInterface"
		cmclient -v inbound GETV "Device.Services.X_ADB_PPPoEProxy.InboundInterface"
		if [ "$enable" = "true" ]; then
			configure_outbound "$outbound"
			configure_inbound "$inbound"
			stop_pppoer
			start_pppoer
		fi
		;;
	Device.Services.X_ADB_PPPoEProxy.Stats)
		[ "$setReset" = "1" ] && reset_stats
		;;
	Device.Services.X_ADB_PPPoEProxy)
		configure_outbound $newOutboundInterface
		configure_inbound $newInboundInterface
		[ "$setReset" = "1" -o "$setEnable" = "1" ] || exit 0
		stop_pppoer
		[ "$newEnable" = "true" ] && start_pppoer
		;;
	esac
}
service_get_stats() {
	local cli_name cli_sid _obj buf
	cmclient -v _obj GETO Device.Services.X_ADB_PPPoEProxy.Client
	for _obj in $_obj; do
		cmclient -v cli_name GETV "%($_obj.ClientInterface).Name"
		cmclient -v cli_sid GETV "$_obj.ClientSessionId"
		read -r buf </sys/class/net/"${cli_name}_$cli_sid"/statistics/tx_packets
		recv=$((recv + buf))
		read -r buf </sys/class/net/"${cli_name}_$cli_sid"/statistics/rx_packets
		sent=$((sent + buf))
		read -r buf </sys/class/net/"${cli_name}_$cli_sid"/statistics/tx_errors
		errrecv=$((errrecv + buf))
		read -r buf </sys/class/net/"${cli_name}_$cli_sid"/statistics/rx_errors
		errsent=$((errsent + buf))
	done
}
if [ $# -eq 2 ] && [ "$1" = "ipifdel" ]; then
	obj="$2"
	help_object_remove_references "Device.Services.X_ADB_PPPoEProxy.OutboundInterface" "$obj"
	help_object_remove_references "Device.Services.X_ADB_PPPoEProxy.InboundInterface" "$obj"
	cmclient -v inIf GETV "Device.Services.X_ADB_PPPoEProxy.InboundInterface"
	cmclient -v outIf GETV "Device.Services.X_ADB_PPPoEProxy.OutboundInterface"
	[ ${#inIf} -eq 0 -o ${#outIf} -eq 0 ] && cmclient SET "Device.Services.X_ADB_PPPoEProxy.Reset" true
	exit 0
fi
case "$op" in
s)
	inifBuf=""
	outifBuf=""
	service_config
	;;
g)
	recv=0 sent=0 errrecv=0 errsent=0
	service_get_stats
	for arg; do
		case "$arg" in
		PacketsSent) echo "$sent" ;;
		PacketsReceived) echo "$recv" ;;
		ErrorsSent) echo "$errsent" ;;
		ErrorsReceived) echo "$errrecv" ;;
		esac
	done
	;;
esac
exit 0
