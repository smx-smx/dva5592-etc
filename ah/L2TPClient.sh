#!/bin/sh
AH_NAME="L2TP-Client"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ppp.sh
XL2TPD_CONF_FILE="/tmp/vpn/l2tp/xl2tpd.conf"
XL2TPD_CONF_FILE_IP="/tmp/vpn/l2tp/xl2tpd-ip.conf"
PPP_OPTIONS_FILE="/tmp/ppp/options.l2tpd"
PPP_PAP_SECRETS="/tmp/ppp/pap-secrets"
PPP_CHAP_SECRETS="/tmp/ppp/chap-secrets"
XL2TPD_SECRETS_FILE="/tmp/vpn/l2tp/xl2tp-secrets"
AWK_SCRIPT='BEGIN {START=0;} /Name:/ {START=1;} /Address / {if (START==1) {split($0,a," ");print(a[3]);exit}}'
mkdir -p /tmp/vpn/l2tp
mkdir -p /var/run/xl2tpd
mkdir -p /tmp/ppp
update_ppp_options_file() {
local cmd_arg_encr="" cmd_arg_prot=""
rm -f $PPP_OPTIONS_FILE
touch $PPP_OPTIONS_FILE
cat > $PPP_OPTIONS_FILE << "EOF"
noaccomp
nopcomp
nobsdcomp
novj
nodeflate
usepeerdns
plugin rp-pppoe.so
plugin pppoatm.so
EOF
echo "lcp-echo-interval $newLCPEcho" >> $PPP_OPTIONS_FILE
echo "user $newUsername" >> $PPP_OPTIONS_FILE
echo "password $newPassword" >> $PPP_OPTIONS_FILE
getAuthenticationProtocolClientCmd "$newAuthenticationProtocol" "cmd_arg_prot"
[ $? -eq $HELPER_PPP_PROTO_MPPE_RET ] && getEncryptionProtocolCmd "$newX_ADB_EncryptionProtocol" "cmd_arg_encr"
printf '%s\n' $cmd_arg_prot >> $PPP_OPTIONS_FILE
echo "$cmd_arg_encr" >> $PPP_OPTIONS_FILE
echo "linkname $newAlias" >> $PPP_OPTIONS_FILE
echo "lldevname lo" >> $PPP_OPTIONS_FILE
echo "ifname $newName" >> $PPP_OPTIONS_FILE
echo "name Client.L2TP" >> $PPP_OPTIONS_FILE
}
update_secrets_file() {
rm -f $XL2TPD_SECRETS_FILE
touch $XL2TPD_SECRETS_FILE
echo "* * $newSecret" > $XL2TPD_SECRETS_FILE
is_pap=`help_strstr "$newAuthenticationProtocol" "PAP"`
if [ -n "$is_pap" ]; then
if [ $changedUsername -eq 0 ]; then
cat $PPP_PAP_SECRETS | grep -v "$newUsername" > $PPP_PAP_SECRETS
else
cat $PPP_PAP_SECRETS | grep -v "$oldUsername" > $PPP_PAP_SECRETS 
fi
echo "$newUsername * $newPassword *" >> $PPP_PAP_SECRETS
fi
is_chap=`help_strstr "$newAuthenticationProtocol" "CHAP"`
if [ -n "$is_chap" ]; then
if [ $changedUsername -eq 0 ]; then
cat $PPP_CHAP_SECRETS | grep -v "$newUsername" > $PPP_CHAP_SECRETS
else
cat $PPP_CHAP_SECRETS | grep -v "$oldUsername" > $PPP_CHAP_SECRETS
fi
echo "$newUsername * $newPassword *" >> $PPP_CHAP_SECRETS
fi
}
update_xl2tpd_conf_file() {
local _newip=`resolve_hostname "$newHostname"`
if [ -n "$_newip" ]; then
echo "lns = $_newip" > $XL2TPD_CONF_FILE_IP
else
	if [ -f $XL2TPD_CONF_FILE_IP ]; then
			local _oldip=`cat $XL2TPD_CONF_FILE_IP | grep lns | cut -d' ' -f 3-`
if [ -n "$_oldip" ]; then
_newip="$_oldip"
fi
else
echo "### $AH_NAME: impossible resolve hostname, pass hostname to L2TP daemon"
_newip="$newHostname"
fi
fi
touch $XL2TPD_CONF_FILE
echo "; $newAlias start" >> $XL2TPD_CONF_FILE
echo "[lac $newAlias]" >> $XL2TPD_CONF_FILE
echo "lns = $_newip" >> $XL2TPD_CONF_FILE
echo "pppoptfile = $PPP_OPTIONS_FILE" >> $XL2TPD_CONF_FILE
echo "redial = yes" >> $XL2TPD_CONF_FILE
echo "redial timeout = 20" >> $XL2TPD_CONF_FILE
echo "tx bps = 100000000" >> $XL2TPD_CONF_FILE
echo "rx bps = 100000000" >> $XL2TPD_CONF_FILE
echo "; $newAlias end" >> $XL2TPD_CONF_FILE
update_secrets_file
update_ppp_options_file
}
resolve_hostname() {
local _ip=""
if help_is_valid_ip "$1" ; then
_ip=$1
else
for dns in `cmclient GETV Device.DNS.Client.Server.*.[Interface=$newInterface].[Enable=true].DNSServer`; do
if nslookup -t 2 "$1" "$dns" > /dev/null 2>&1 ; then
_ip=`nslookup -t 2 "$1" "$dns" | awk "$AWK_SCRIPT"`
if help_is_valid_ip "$_ip" ; then
break;
else
_ip=""
fi
fi
done
fi
echo $_ip
}
update_static_route() {
local _oldip
local _newip
local setm
_oldip=`resolve_hostname "$oldHostname"`
_newip=`resolve_hostname "$newHostname"`
i=`cmclient GETO "Device.Routing.Router.IPv4Forwarding.[Interface=$oldInterface].[StaticRoute=true].[DestIPAddress=$_oldip].[Alias=$1]"`
if [ -z "$_newip" ]; then
if [ -n "$i" ]; then
cmclient DEL "$i" > /dev/null
fi
else
if [ -z "$i" ]; then
i_idx=`cmclient ADD "Device.Routing.Router.1.IPv4Forwarding"`
i="Device.Routing.Router.1.IPv4Forwarding.$i_idx"
fi
setm="$i.Enable=true"
setm="$setm	$i.Alias=$1"
setm="$setm	$i.Interface=$newInterface"
setm="$setm	$i.StaticRoute=true"
setm="$setm	$i.X_ADB_AutoGateway=true"
setm="$setm	$i.DestIPAddress=$_newip"
setm="$setm	$i.Interface=$newInterface"
cmclient SETM "$setm" > /dev/null
fi
}
restore_default_route() {
local _i
local _router="$1"
_i=`cmclient GETO "Device.IP.Interface.*.[X_ADB_DefaultRoute=true].[Enable=true].[Status=Up]"`
for def_route in `cmclient GETO "$_router.IPv4Forwarding.*.[Interface=$_i].[DestIPAddress=].[Enable=false]"`
do
cmclient SET "$def_route.Enable" "true"
break
done
}
start_l2tp_tunnel() {
is_client_running=`ps eaf | grep $XL2TPD_CONF_FILE | grep -v grep`
if [ -z "$is_client_running" ]; then
restore_default_route "Device.Routing.Router.1"
update_xl2tpd_conf_file
echo "### $AH_NAME: updating static route ###"
update_static_route "$newAlias"
echo "### $AH_NAME: xl2tpd -c $XL2TPD_CONF_FILE ###"
xl2tpd -c $XL2TPD_CONF_FILE
touch /var/run/xl2tpd/l2tp-control
echo "c $newAlias > /var/run/xl2tpd/l2tp-control" 
echo "c $newAlias" > /var/run/xl2tpd/l2tp-control
fi
}
kill_l2tp_tunnel() {
if [ -f "$XL2TPD_CONF_FILE" ]; then
echo "d $newAlias > /var/run/xl2tpd/l2tp-control" 
echo "d $newAlias" > /var/run/xl2tpd/l2tp-control
sleep 2
sed -i "/$newAlias start/,/$newAlias end/d" $XL2TPD_CONF_FILE
fi
numl2tpobj=`cmclient GETO Device.X_ADB_VPN.Client.L2TP | wc -l`
if [ "$numl2tpobj" = "1" ]; then
killall xl2tpd
sleep 2
fi
}
service_reconf() {
if [ $changedEnable -eq 1 ]; then
if [ "$newEnable" = "false" ]; then
new_status="Disconnected"
kill_l2tp_tunnel
else
new_status=""
fi
else
if [ "$newEnable" = "true" ]; then
new_status="$newStatus"
case $new_status in
"Connected" | "Connecting" )
if [ $changedStatus -eq 0 ]; then
kill_l2tp_tunnel
new_status=""
fi
;;
"Disconnected" )
new_status=""
;;
* )
kill_l2tp_tunnel
new_status=""
;;
esac
else
new_status="Disconnected"
fi
fi
if [ -z "$newInterface" ]; then
new_status="Disconnected"
else
ipif_status=`cmclient GETV "$newInterface.Status"`
if [ "$ipif_status" != "Up" ]; then
new_status="Disconnected"
fi
fi
if [ $changedReset -eq 1 ]; then
if [ "$newReset" = "true" ]; then
kill_l2tp_tunnel
new_status=""
fi
fi
if [ -z "$new_status" ]; then
if [ -z "$newHostname" ] || [ -z "$newAuthenticationProtocol" ]; then
new_status="Unconfigured"
elif [ "$newAuthenticationProtocol" != "none" ]; then
if [ -z "$newUsername" ] || [ -z "$newPassword" ]; then
new_status="Unconfigured"
fi
fi
fi
if [ $changedX_ADB_EncryptionProtocol -eq 1 ]; then
if [ "$newX_ADB_EncryptionProtocol" = "None" ]; then
cmclient SETE "$obj.EncryptionProtocol" "None"
else
cmclient SETE "$obj.EncryptionProtocol" "MPPE"
fi
fi
if [ -z "$new_status" ]; then
start_l2tp_tunnel
new_status="Connecting"
fi
if [ "$new_status" != "$newStatus" ]; then
cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "$new_status" > /dev/null
fi
}
service_config() {
if [ $changedDefaultRoute -eq 1 -o $changedSubnetMask -eq 1 ]; then
return
fi
service_reconf
}
service_delete() {
cmclient -u "${AH_NAME}${obj}" SET "$obj.Enable" false > /dev/null
kill_l2tp_tunnel
i=`cmclient GETO Device.Routing.Router.IPv4Forwarding.[Alias=$newAlias]`
if [ -n "$i" ]; then
cmclient DEL "$i"
fi
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
