#!/bin/sh
#udp:auth-fail,ppp,*
#sync:max=3
EH_NAME="PPPAuthFail"
obj="$LINKNAME"
[ -f /etc/ah/helper_ARS.sh ] && . /etc/ah/helper_ARS.sh
case "$PPP_EXIT_STATUS" in
"10"|"11"|"19")
case "$NAME" in
*"Server.PPTP"*)
logger -t VPNPPTP -p 3 "ARS 2 - Tunnel negotiation failed with client $CLIENT_IP"
;;
*"Client.PPTP"*)
cmclient -v serverip GETV Device.X_ADB_VPN.Client.PPTP.[Alias=$LINKNAME].Hostname
logger -t VPNPPTP -p 3 "ARS 3 - Tunnel negotiation failed with server $serverip"
;;
*"Server.L2TP"*)
logger -t VPNL2TP -p 3 "ARS 2 - Tunnel negotiation failed with client $CLIENT_IP"
	;;
*"Client.L2TP"*)
cmclient -v serverip GETV Device.X_ADB_VPN.Client.L2TP.[Alias=$LINKNAME].Hostname
logger -t VPNL2TP -p 3 "ARS 3 - Tunnel negotiation failed with server $serverip"
;;
esac
;;
"16")
case "$NAME" in
*"Server.PPTP"*)
logger -t VPNPPTP -p 3 "ARS 4 - Lost connection with client $CLIENT_IP"
;;
*"Client.PPTP"*)
cmclient -v serverip GETV Device.X_ADB_VPN.Client.PPTP.[Alias=$LINKNAME].Hostname
logger -t VPNPPTP -p 3 "ARS 5 - Lost connection with server $serverip"
;;
*"Server.L2TP"*)
logger -t VPNL2TP -p 3 "ARS 4 - Lost connection with client $CLIENT_IP"
;;
*"Client.L2TP"*)
cmclient -v serverip GETV Device.X_ADB_VPN.Client.L2TP.[Alias=$LINKNAME].Hostname
logger -t VPNL2TP -p 3 "ARS 5 - Lost connection with server $serverip"
;;
esac
;;
esac
case "$PPP_EXIT_STATUS" in
"19") # PPPD status = EXIT_AUTH_TOPEER_FAILED
if grep -qs ERROR_AUTHENTICATION_FAILURE /tmp/ppp/${LINKNAME}-lastconnerr; then
cmclient -u "$EH_NAME" SET "${LINKNAME}.LastConnectionError" "ERROR_AUTHENTICATION_FAILURE" > /dev/null
logger -t "cm" "PPP Interface ${IFNAME} Session Down: User/password wrong" -p 7
cmclient -v ipcpenable GETV $obj.IPCPEnable
cmclient -v local_ip GETV $obj.IPCP.LocalIPAddress
cmclient -v remote_ip GETV $obj.IPCP.RemoteIPAddress
if [ -n "$remote_ip" -a -n "$local_ip" -a "$ipcpenable" = "true" ]
then
[ -f /etc/ah/helper_ARS.sh ] && count_ppp_failures "4" "auth"
fi
cmclient -v remote_iface_id GETV $obj.IPv6CP.RemoteInterfaceIdentifier
cmclient -v local_iface_id GETV $obj.IPv6CP.LocalInterfaceIdentifier
cmclient -v ipv6cpenable GETV $obj.IPv6CPEnable
if [ -n "$remote_iface_id" -a -n "$local_iface_id" -a "$ipv6cpenable" = "true" ]
then
logger -t "cm" "PPP Interface ${IFNAME} IPv6 Session Down: User/password wrong" -p 7
[ -f /etc/ah/helper_ARS.sh ] && count_ppp_failures "6" "auth"
fi
fi
;;
"10") # PPPD status = EXIT_NEGOTIATION_FAILED
last_conn_err=""
[ -e /tmp/ppp/${LINKNAME}-lastconnerr ] && read last_conn_err < /tmp/ppp/${LINKNAME}-lastconnerr
[ -n "$last_conn_err" -a -z "${last_conn_err##ERROR_NEGOTIATION_FAILED}" ] && cmclient -u "$EH_NAME" SET "${LINKNAME}.LastConnectionError" "ERROR_NEGOTIATION_FAILED"
cmclient -v ipcpenable GETV $obj.IPCPEnable
cmclient -v local_ip GETV $obj.IPCP.LocalIPAddress
cmclient -v remote_ip GETV $obj.IPCP.RemoteIPAddress
if [ -n "$remote_ip" -a -n "$local_ip" -a "$ipcpenable" = "true" ]
then
[ -f /etc/ah/helper_ARS.sh ] && count_ppp_failures "4" "neg"
fi
	cmclient -v remote_iface_id GETV $obj.IPv6CP.RemoteInterfaceIdentifier
cmclient -v local_iface_id GETV $obj.IPv6CP.LocalInterfaceIdentifier
cmclient -v ipv6cpenable GETV $obj.IPv6CPEnable
if [ -n "$remote_iface_id" -a -n "$local_iface_id" -a "$ipv6cpenable" = "true" ]
then
[ -f /etc/ah/helper_ARS.sh ] && count_ppp_failures "6" "neg"
fi
;;
esac
exit 0
