#!/bin/sh
AH_NAME="PPTP-Server"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ppp.sh
PPPD_OPTIONS_FILE="/tmp/ppp/options.pptp"
PPPD_SECRETS_FILE="/tmp/ppp/secrets.pptp"
PPTP_CONF_FILE="/tmp/vpn/pptp/pptpd.conf"
PPTP_PID_FILE="/tmp/vpn/pptp/pptpd.pid"
start_pptpd_daemon() {
pptp_conf_file_update $1
pppd_options_file_update $1
pptpd -p "$PPTP_PID_FILE.$1" -c "$PPTP_CONF_FILE.$1"
}
pptp_conf_file_update() {
local end_ip ip_range local_ip
end_ip=`echo "$newMaxAddress" | cut -d "." -f4`
ip_range=$newMinAddress"-"$end_ip
cmclient -v local_ip GETV "Device.X_ADB_VPN.Server.PPTP.*.MinAddress"
local_ip="${local_ip%.*}.1"
{
echo "ppp /usr/sbin/pppd"
echo "listen $1"
echo "localip $local_ip"
echo "remoteip $ip_range"
echo "option $PPPD_OPTIONS_FILE.$1"
} > "$PPTP_CONF_FILE.$1"
if [ -n "$newIdleDisconnectTime" ]; then
echo "stimeout $newIdleDisconnectTime" >> "$PPTP_CONF_FILE.$1"
fi
}
pppd_options_file_update() {
local ipaddr=$1
local requireauth=0
local unit="2`printf %.2d $((${obj##*.} - 1))`00"
local cmd_arg_encr=""
{
echo 'ipcp-accept-local'
echo 'ipcp-accept-remote'
echo "ms-dns $ipaddr"
echo 'mtu 1280'
echo 'mru 1280'
echo 'nodefaultroute'
echo "unit $unit"
echo "linkname $newAlias"
echo "lldevname lo"
echo "name Server.PPTP"
case ",$newAuthenticationProtocol," in
*,PAP,*)
echo "require-pap"
cmclient SETE "$obj.EncryptionProtocol" "None" > /dev/null
requireauth=1
;;
*)
echo "refuse-pap"
;;
esac
case ",$newAuthenticationProtocol," in
*,CHAP,*)
echo "require-chap"
cmclient SETE "$obj.EncryptionProtocol" "None" > /dev/null
requireauth=1
;;
*)
echo "refuse-chap"
;;
esac
case ",$newAuthenticationProtocol," in
*,MS-CHAP,*)
echo "require-mschap"
requireauth=1
cmd_arg_encr="mppe"
;;
*)
echo "refuse-mschap"
;;
esac
case ",$newAuthenticationProtocol," in
*,MS-CHAPv2,*)
echo "require-mschap-v2"
cmd_arg_encr="mppe"
requireauth=1
;;
*)
echo "refuse-mschap-v2"
;;
esac
if [ ${#cmd_arg_encr} -ne 0 ]; then
getEncryptionProtocolCmd "$newX_ADB_EncryptionProtocol" "cmd_arg_encr"
echo "$cmd_arg_encr"
fi
if [ $requireauth -eq 1 ]; then
echo 'auth'
echo "secrets-file $PPPD_SECRETS_FILE.$ipaddr"
else
echo 'noauth'
fi
} > "$PPPD_OPTIONS_FILE.$ipaddr"
if [ $changedX_ADB_EncryptionProtocol -eq 1 ]; then
if [ "$newX_ADB_EncryptionProtocol" = "None" ]; then
cmclient SETE "$obj.EncryptionProtocol" "None"
else
if [ "$newAuthenticationProtocol" = "MS-CHAP" ] ||
[ "$newAuthenticationProtocol" = "MS-CHAPv2" ]; then
cmclient SETE "$obj.EncryptionProtocol" "MPPE"
fi
fi
fi
[ $requireauth -eq 1 ] && generate_secrets "$obj" "$ipaddr"
}
generate_secrets() {
local _obj=$1
local ifname=$2
local user
local userobj
local username
local password
set -f
IFS=,
cmclient -v userobj GETV "$_obj".Users
set -- $userobj
set +f
for userobj; do
cmclient -v user GETO "$userobj".[Enable=true]
for user in $user; do
cmclient -v username GETV "$user".Username
cmclient -v password GETV "$user".Password
echo "$username * $password *"
done
done > $PPPD_SECRETS_FILE.$ifname
}
kill_pptpd_daemon() {
local pidex=
if [ -e "$PPTP_PID_FILE.$1" ]; then
pidex=`cat $PPTP_PID_FILE.$1`
if [ -n "$pidex" ]; then
rm -f "$PPTP_PID_FILE.$1"
kill -9 $pidex
fi
fi
rm -f "$PPTP_CONF_FILE.$1"
rm -f "$PPPD_OPTIONS_FILE.$1"
rm -f "$PPPD_SECRETS_FILE.$1"
}
get_ip_addr() {
local ip
local ipaddr
for ip in `cmclient GETO "$1.IPv4Address.[Enable=true]"`
do
ipaddr=`cmclient GETV $ip.IPAddress`
if [ -n "$ipaddr" ]; then
echo $ipaddr
break;
fi
done
}
service_config() {
local refresh=0
local ipaddr
case "$obj" in
Device.X_ADB_VPN.Users.User.*)
for x in Enable Username Password; do
eval [ \"\$changed$x\" = 1 ] && refresh=1
done
[ "$refresh" = "0" ] && return
cmclient -v x GETO "Device.X_ADB_VPN.Server.PPTP.[Users>$obj]"
for x in $x; do
local interface=`cmclient GETV "$x".Interface`
[ -n "$interface" ] || \
cmclient -v interface GETO "Device.IP.Interface.*.[X_ADB_DefaultRoute=true]"
ipaddr=`get_ip_addr $interface`
generate_secrets "$x" "$ipaddr"
done
;;
Device.X_ADB_VPN.Server.PPTP.*)
ipaddr=`get_ip_addr $newInterface`
if [ "$newEnable" = "true" ]; then
if [ -z "$newMinAddress" ] || [ -z "$newMaxAddress" ]; then
new_status="Error_Misconfigured"
else
new_status="Enabled"
fi
else
new_status="Disabled"
fi
if [ -n "$ipaddr" ]; then
kill_pptpd_daemon "$ipaddr"
fi
if [ "$new_status" = "Enabled" ]; then
if [ -n "$ipaddr" ]; then
start_pptpd_daemon "$ipaddr"
ret=$?
if [ "$ret" -ne $OK ]; then
new_status="Error"
logger -p daemon.err -t VPNPPTP ARS 1 - Unable to start service
				fi
else
new_status="Error"
logger -p daemon.err -t VPNPPTP ARS 1 - Unable to start service
fi
fi
cmclient SET -u "${AH_NAME}${obj}" "$obj".Status "$new_status" >/dev/null
;;
esac
}
kill_pptpd_relay() {
local locIF=`cmclient GETV "$obj".Interface`
local llayer=`cmclient GETV "$locIF".LowerLayers`
local llayerName=`cmclient GETV "$llayer".Name`
if [ -e "/var/run/${llayerName}_pptpRly.pid" ]; then
pidRly="`cat /var/run/${llayerName}_pptpRly.pid`"
if [ -n "$pidRly" ]; then
rm -f "/var/run/${llayerName}_pptpRly.pid"
kill -9 $pidRly
fi
fi
}
start_pptpd_relay() {
pptpd -C 1 -l "$1" -a "$2" -p "$4"_pptpRly.pid -A "$3"
}
service_config_relay() {
local locIF=
local llayer=
local llayerName=
if [ "$changedStatus" = "1" ]; then
return
fi
kill_pptpd_relay
new_status="Disabled"
if [ "$newEnable" = "true" ] && [ "$newPPPRelayEnable" = "true" ]; then
if [ -n "$newPPPRelayOutBoundInterface" ]; then
locIF=`cmclient GETV "$obj".Interface`
llayer=`cmclient GETV "$locIF".LowerLayers`
llayerName=`cmclient GETV "$llayer".Name`
if [ "$locIF" != "" ]; then
cmclient -v ip_status GETV "$locIF.Status"
if [ "$ip_status" = "Up" ]; then
for ipaddr in `cmclient GETV "$locIF.IPv4Address.*.IPAddress"`
do
if [ -n "$ipaddr" ]; then
break;
fi
done
fi
fi
RelPVC=`cmclient GETV "$newPPPRelayOutBoundInterface".DestinationAddress`
Enc=`cmclient GETV "$newPPPRelayOutBoundInterface".Encapsulation`
if [ "$Enc" = "VCMUX" ]; then
Enc="-v"
else
Enc="-l"
fi
PRelPVC=`echo "$RelPVC" | sed 's%/%.%'`
start_pptpd_relay "$ipaddr" "$PRelPVC" "$Enc" "$llayerName"
ret=$?
if [ "$ret" -eq $OK ]; then
new_status="Enabled"
else
new_status="Error"
fi
else
new_status="Error_Misconfigured"
echo "$AH_NAME: Relay IF not yet available" > /dev/console 
fi
fi
cmclient SET -u "${AH_NAME}${obj}" "$obj".Status "$new_status" >/dev/null
}
service_delete_relay() {
kill_pptpd_relay
}
service_delete() {
case "$obj" in
Device.X_ADB_VPN.Users.User.*)
local pptpobj
local oldusers
local users
local userobj
for pptpobj in `cmclient GETO "Device.X_ADB_VPN.Server.PPTP.[Users>$obj]"`; do
set -f
IFS=,
cmclient -v oldusers GETV "$pptpobj.Users"
set -- $oldusers
set +f
users=
for userobj; do
[ "$userobj" = "$obj" ] || \
users="${users:+$users,}$userobj"
done
[ "$oldusers" != "$users" ] && cmclient SET "$pptpobj.Users" "$users" >/dev/null
done
;;
Device.X_ADB_VPN.Server.PPTP.*)
local ipaddr=`get_ip_addr $newInterface`
kill_pptpd_daemon "$ipaddr"
;;
esac
}
case "$op" in
s)
if [ "$changedPPPRelayEnable" = "1" ] || [ "$newPPPRelayEnable" = "true" ]; then
service_config_relay
elif [ "$setEnable" = "1" ] || [ "$newEnable" = "true" ]; then
service_config
fi
;;
d)
if [ "$oldPPPRelayEnable" = "true" ]; then
service_delete_relay
else
service_delete
fi
;;
esac
exit 0
