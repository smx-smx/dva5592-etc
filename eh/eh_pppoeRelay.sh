#!/bin/sh
#udp:*,ppp-relay,*
#sync:max=1
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/IPv6_helper_firewall.sh
case $OP in
INIT | STOP)
	cmclient DEL "Device.Services.X_ADB_PPPoEProxy.Client."
	;;
CREATE_SESSION)
	[ ${#CLI_MAC_ADDRESS} -ne 0 -a ${#SRV_MAC_ADDRESS} -ne 0 -a ${#CLI_SES_ID} -ne 0 -a ${#SRV_SES_ID} -ne 0 ] || exit 0
	cmclient -v _obj GETO "Device.Services.X_ADB_PPPoEProxy.Client.[ClientSessionId=$CLI_SES_ID]"
	[ ${#_obj} -eq 0 ] || exit 0
	[ -f /sys/class/net/${CLI_IFACE}/address -a -f /sys/class/net/${SRV_IFACE}/address ] || exit 0
	read lmac </sys/class/net/${CLI_IFACE}/address
	read rmac </sys/class/net/${SRV_IFACE}/address
	[ ${#lmac} -ne 0 -a ${#rmac} -ne 0 ] || exit 0
	echo "$CLI_IFACE ${CLI_IFACE}_$CLI_SES_ID $CLI_SES_ID dstmac $SRV_MAC_ADDRESS srcmac $lmac" >/proc/net/cnetdev/create
	echo "$SRV_IFACE ${SRV_IFACE}_$SRV_SES_ID $SRV_SES_ID dstmac $CLI_MAC_ADDRESS srcmac $rmac" >/proc/net/cnetdev/create
	brctl addbr "pr${CLI_SES_ID}_$SRV_SES_ID"
	brctl setfd "pr${CLI_SES_ID}_$SRV_SES_ID" 0
	brctl addif "pr${CLI_SES_ID}_$SRV_SES_ID" "${CLI_IFACE}_$CLI_SES_ID"
	brctl addif "pr${CLI_SES_ID}_$SRV_SES_ID" "${SRV_IFACE}_$SRV_SES_ID"
	ip link set dev "pr${CLI_SES_ID}_$SRV_SES_ID" up
	help_iptables -I ForwardAllow_PPPoERelay -i "pr${CLI_SES_ID}_$SRV_SES_ID" -j ACCEPT
	help_iptables -I ForwardAllow_PPPoERelay -o "pr${CLI_SES_ID}_$SRV_SES_ID" -j ACCEPT
	help_ip6tables -I ForwardAllow_PPPoERelay -i "pr${CLI_SES_ID}_$SRV_SES_ID" -j ACCEPT
	help_ip6tables -I ForwardAllow_PPPoERelay -o "pr${CLI_SES_ID}_$SRV_SES_ID" -j ACCEPT
	cli_intf=$(help_obj_from_ifname_get "$CLI_IFACE")
	srv_intf=$(help_obj_from_ifname_get "$SRV_IFACE")
	cmclient -v _obj ADD "Device.Services.X_ADB_PPPoEProxy.Client"
	_obj="Device.Services.X_ADB_PPPoEProxy.Client.$_obj"
	setm="$_obj.ClientSessionId=$CLI_SES_ID"
	setm="$setm	$_obj.ServerSessionId=$SRV_SES_ID"
	setm="$setm	$_obj.ClientPhysAddress=$CLI_MAC_ADDRESS"
	setm="$setm	$_obj.ServerPhysAddress=$SRV_MAC_ADDRESS"
	setm="$setm	$_obj.ClientInterface=$cli_intf"
	setm="$setm	$_obj.ServerInterface=$srv_intf"
	cmclient SETM "$setm"
	;;
FREE_SESSION)
	[ ${#CLI_MAC_ADDRESS} -ne 0 -a ${#CLI_SES_ID} -ne 0 ] || exit 0
	cmclient -v _ok DEL "Device.Services.X_ADB_PPPoEProxy.Client.[ClientSessionId=$CLI_SES_ID]"
	case "$_ok" in
	*ERROR*)
		exit 0
		;;
	esac
	ip link set dev "pr${CLI_SES_ID}_$SRV_SES_ID" down
	brctl delbr "pr${CLI_SES_ID}_$SRV_SES_ID"
	help_iptables -D ForwardAllow_PPPoERelay -i "pr${CLI_SES_ID}_$SRV_SES_ID" -j ACCEPT
	help_iptables -D ForwardAllow_PPPoERelay -o "pr${CLI_SES_ID}_$SRV_SES_ID" -j ACCEPT
	help_ip6tables -D ForwardAllow_PPPoERelay -i "pr${CLI_SES_ID}_$SRV_SES_ID" -j ACCEPT
	help_ip6tables -D ForwardAllow_PPPoERelay -o "pr${CLI_SES_ID}_$SRV_SES_ID" -j ACCEPT
	echo "${CLI_IFACE}_$CLI_SES_ID" >/proc/net/cnetdev/delete
	echo "${SRV_IFACE}_$SRV_SES_ID" >/proc/net/cnetdev/delete
	;;
esac
exit 0
