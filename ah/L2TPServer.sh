#!/bin/sh
AH_NAME="L2TP-Server"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_ppp.sh
generate_config() {
local ifname=$1 requireauth=0 local_ip ipaddr unit cmd_arg_encr=""
unit="1`printf %.2d $((${obj##*.} - 1))`00"
read -r ipaddr <<-EOF
`cmclient GETV "$newInterface".IPv4Address.[Enable=true].IPAddress`
EOF
[ -z "$ipaddr" ] && return 1
cmclient -v local_ip GETV "Device.X_ADB_VPN.Server.L2TP.*.MinAddress"
local_ip="${local_ip%.*}.1"
mkdir -p /tmp/xl2tpd/$ifname/
{
echo '[global]'
echo "listen-addr = $ipaddr"
echo
echo "[lns default]"
echo "assign ip = yes"
echo "ip range = $newMinAddress-$newMaxAddress"
echo "local ip = $local_ip"
echo "length bit = yes"
echo "pppoptfile = /tmp/xl2tpd/$ifname/options.xl2tpd"
} > /tmp/xl2tpd/$ifname/xl2tpd.conf
{
echo 'ipcp-accept-local'
echo 'ipcp-accept-remote'
echo "ms-dns $ipaddr"
echo 'mtu 1280'
echo 'mru 1280'
echo 'nodefaultroute'
echo "linkname $newAlias"
echo "lldevname lo"
echo "unit $unit"
case ",$newAuthenticationProtocol," in
*,PAP,*)
echo "require-pap"
requireauth=1
;;
*)
echo "refuse-pap"
;;
esac
case ",$newAuthenticationProtocol," in
*,CHAP,*)
echo "require-chap"
requireauth=1
;;
*)
echo "refuse-chap"
;;
esac
case ",$newAuthenticationProtocol," in
*,MS-CHAP,*)
echo "require-mschap"
cmd_arg_encr="mppe"
requireauth=1
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
echo "secrets-file /tmp/xl2tpd/$ifname/secrets"
else
echo 'noauth'
fi
echo "name Server.L2TP"
} > /tmp/xl2tpd/$ifname/options.xl2tpd
[ $requireauth -eq 1 ] && generate_secrets "$obj" "$ifname"
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
done > /tmp/xl2tpd/$ifname/secrets
}
service_config() {
local refresh=0 x ifname
case "$obj" in
Device.X_ADB_VPN.Users.User.*)
for x in Enable Username Password; do
eval [ \"\$changed$x\" = 1 ] && refresh=1
done
[ "$refresh" = "0" ] && return
cmclient -v x GETO "Device.X_ADB_VPN.Server.L2TP.[Users>$obj]"
for x in $x; do
local interface=`cmclient GETV "$x".Interface`
[ -n "$interface" ] || \
cmclient -v interface GETO "Device.IP.Interface.*.[X_ADB_DefaultRoute=true]"
help_lowlayer_ifname_get ifname "$interface"
generate_secrets "$x" "$ifname"
done
;;
Device.X_ADB_VPN.Server.L2TP.*)
for x in AuthenticationProtocol Interface MinAddress MaxAddress Users; do
eval [ \"\$changed$x\" = 1 ] && refresh=1
done
[ "$refresh" = "0" -a "$setEnable" = "0" ] && return
[ -n "$newInterface" ] || \
cmclient -v newInterface GETO "Device.IP.Interface.*.[X_ADB_DefaultRoute=true]"
help_lowlayer_ifname_get ifname "$newInterface"
if [ -f "/tmp/xl2tpd/$ifname/xl2tpd.pid" ]; then
kill `cat "/tmp/xl2tpd/$ifname/xl2tpd.pid"` 2>/dev/null
fi
if [ "$newEnable" = "true" ]; then
if [ -z "$newMinAddress" -o -z "$newMaxAddress" ]; then
cmclient SET -u "${AH_NAME}${obj}" "$obj".Status "Error_Misconfigured" >/dev/null
return
fi
generate_config "$ifname"
xl2tpd -c /tmp/xl2tpd/$ifname/xl2tpd.conf -p /tmp/xl2tpd/$ifname/xl2tpd.pid -C /tmp/xl2tpd/$ifname/l2tp-control
cmclient SET -u "${AH_NAME}${obj}" "$obj".Status "Enabled" >/dev/null
else
:
cmclient SET -u "${AH_NAME}${obj}" "$obj".Status "Disabled" >/dev/null
fi
;;
esac
}
service_delete() {
case "$obj" in
Device.X_ADB_VPN.Users.User.*)
local l2tpobj
local oldusers
local users
local userobj
for l2tpobj in `cmclient GETO "Device.X_ADB_VPN.Server.L2TP.[Users>$obj]"`; do
set -f
IFS=,
cmclient -v oldusers GETV "$l2tpobj.Users"
set -- $oldusers
set +f
users=
for userobj; do
[ "$userobj" = "$obj" ] || \
users="${users:+$users,}$userobj"
done
[ "$oldusers" != "$users" ] && cmclient SET "$l2tpobj.Users" "$users" >/dev/null
done
;;
Device.X_ADB_VPN.Server.L2TP.*)
local ifname
help_lowlayer_ifname_get ifname "$oldInterface"
rm -rf "/tmp/xl2tpd/$ifname/"
;;
esac
}
case "$op" in
d)
service_delete
;;
s)
service_config
;;
esac
exit 0
