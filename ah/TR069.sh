#!/bin/sh
if [ "$user" = "TR069" ]; then
exit 0
fi
AH_NAME="TR069"
PIDFILE="/tmp/cwmp.pid"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_conflicts.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_svc.sh
. /etc/ah/helper_provisioning.sh
reconf_acs_fw()
{
local p _tmp _i _e _newX_ADB_ConnectionRequestInterface="$1" _newX_ADB_ConnectionRequestPort="$2" \
_newX_ADB_AccessControl="$3" _newX_ADB_AccessControlEnable="$4"
obj=Device.ManagementServer help_check_conflicts 1 "$_newX_ADB_ConnectionRequestInterface" "$_newX_ADB_ConnectionRequestPort" || exit 1
help_lowlayer_ifname_get ifname "$_newX_ADB_ConnectionRequestInterface"
[ -z "$ifname" ] && return
help_iptables -t nat -F NATSkip_ACS
help_iptables -t nat -A NATSkip_ACS -i "${ifname}" -p tcp --dport "${_newX_ADB_ConnectionRequestPort}" -j ACCEPT
help_iptables -F CWMPIn
help_iptables -A CWMPIn -i lo -j RETURN
help_iptables -A CWMPIn ! -p tcp -j RETURN
cmclient -v _tmp GETV Device.DeviceInfo.X_ADB_UpgradeInProgress
if [ "$_tmp" = "true" ]; then
help_iptables -N DwlInProgress
help_iptables -A DwlInProgress -p tcp -i "${ifname}"+ -m multiport --dport "$((_newX_ADB_ConnectionRequestPort+2))":"$((_newX_ADB_ConnectionRequestPort+11))" -j ACCEPT
help_iptables -A CWMPIn -j DwlInProgress
fi
help_iptables -A CWMPIn -p tcp ! --dport "${_newX_ADB_ConnectionRequestPort}" -j RETURN
help_iptables -F CWMPOut
help_iptables -A CWMPOut -o lo -j RETURN
help_iptables -A CWMPOut ! -p tcp -j RETURN
help_iptables -A CWMPOut -p tcp ! --sport "$((_newX_ADB_ConnectionRequestPort-1)):$((_newX_ADB_ConnectionRequestPort+1))" -j RETURN
if [ "$_newX_ADB_AccessControlEnable" = "true" ]; then
set -f
IFS=","
set -- $_newX_ADB_AccessControl
unset IFS
set +f
for a; do
help_iptables -A CWMPIn -s "${a}" -i "${ifname}"+ -j ACCEPT
help_iptables -A CWMPOut -d "${a}" -o "${ifname}"+ -j ACCEPT
done
help_iptables -A CWMPIn -j LOG --log-prefix "CWMP_ACL:" --log-level 2
else
help_iptables -A CWMPIn -i "${ifname}"+ -j ACCEPT
help_iptables -A CWMPOut -o "${ifname}"+ -j ACCEPT
fi
help_iptables -A CWMPIn -i "${ifname}"+ -j DROP
help_iptables -A CWMPOut -o "${ifname}"+ -j DROP
help_reconfigure_nat_conflicts "$_newX_ADB_ConnectionRequestInterface"
}
cwmpShutdown()
{
local p conn_req_if=""
[ -f "$PIDFILE" ] && help_svc_stop cwmp "$PIDFILE" "15"
help_iptables -t nat -F NATSkip_ACS
help_iptables -F CWMPIn
cmclient -v conn_req_if GETV "Device.ManagementServer.X_ADB_ConnectionRequestInterface"
help_reconfigure_nat_conflicts "$conn_req_if"
}
if [ $# -eq 2 ] && [ "$1" = "ipifdel" ]; then
obj="$2"
cmclient -v connReqIf GETV "Device.ManagementServer.X_ADB_ConnectionRequestInterface"
cmclient -v informIf GETV "Device.ManagementServer.X_ADB_InformInterface"
[ "$informIf" = "$obj" ] && cmclient SET "Device.ManagementServer.X_ADB_InformInterface" ""
[ "$connReqIf" = "$obj" ] && cmclient SET "Device.ManagementServer.X_ADB_ConnectionRequestInterface" ""
exit 0
fi
cmclient -v connReqIf GETV Device.ManagementServer.X_ADB_ConnectionRequestInterface
if [ $# -eq 2 ] && [ "$1" = "IP_IF_CHANGED" ]; then
setmquery=""
if [ "$connReqIf" != $2 ]; then
[ "$2" != "ANY" ] && exit 0
fi
cmclient -v _t GETV Device.IP.IPv6Enable
cmclient -v _p GETV Device.ManagementServer.X_ADB_IPv6Preferred
if [ "$_t" = "true" -a "$_p" = "true" ]; then
cmclient -v newAddr GETV "${connReqIf}".IPv6Address.+.[Status=Enabled].[IPAddressStatus!Invalid].IPAddress
if [ -z "$newAddr" ]; then
cmclient -v newAddr GETV "${connReqIf}".IPv4Address.+.IPAddress
for newAddr in $newAddr; do
break
done
IPv6Addr=0
else
local single
for single in $newAddr; do
case $single in
fe80*)
;;
*)
found="y"
break
;;
esac
done
if [ "$found" = "y" ]; then
newAddr="$single"
IPv6Addr=1
else
cmclient -v newAddr GETV "${connReqIf}".IPv4Address.+.IPAddress
for newAddr in $newAddr; do
break
done
IPv6Addr=0
fi
fi
else
cmclient -v newAddr GETV "${connReqIf}".IPv4Address.+.IPAddress
for newAddr in $newAddr; do
break
done
IPv6Addr=0
fi
echo "### TR069 ConnectionRequestInterface: $connReqIf ($newAddr)" > /dev/console
cmclient -v port GETV Device.ManagementServer.X_ADB_ConnectionRequestPort
if [ -n "$newAddr" ]; then
cmclient -v path GETV Device.ManagementServer.X_ADB_ConnectionRequestPath
cmclient -v _tmp GETV Device.ManagementServer.X_ADB_ConnectionRequestRandomPath
if [ "$_tmp" = "true" ]; then
randPath=$(tr -Cd "a-zA-Z0-9" < /dev/urandom | head -c 10)
path=$path$randPath
fi
[ "$IPv6Addr" = "1" ] &&\
newcrurl="http://[${newAddr}]:${port}/${path}" || \
newcrurl="http://${newAddr}:${port}/${path}"
cmclient -v _t GETV Device.ManagementServer.ConnectionRequestURL
if [ "$newcrurl" != "$_t" ]; then
[ -z "$setmquery" ] &&\
setmquery="Device.ManagementServer.ConnectionRequestURL=${newcrurl}" ||\
setmquery="$setmquery	Device.ManagementServer.ConnectionRequestURL=${newcrurl}"
fi
cmclient -v session GETV Device.ManagementServer.X_ADB_CWMPState.SessionInProgress
[ "$session" = "false" -a -f /tmp/cwmp.pid ] && pkill -SIGUSR1 -x cwmp
fi
[ -n "$setmquery" ] && cmclient -u TR069 SETM "$setmquery"
cmclient -v access_ctrl GETV Device.ManagementServer.X_ADB_AccessControl
cmclient -v access_ctrl_en GETV Device.ManagementServer.X_ADB_AccessControlEnable
reconf_acs_fw "$connReqIf" "$port" "$access_ctrl" "$access_ctrl_en"
exit 0
fi
if help_is_changed X_ADB_ConnectionRequestPort X_ADB_ConnectionRequestPath \
X_ADB_ConnectionRequestRandomPath X_ADB_ConnectionRequestInterface \
X_ADB_IPv6Preferred; then
if [ "$newX_ADB_IPv6Preferred" = "true" ]; then
cmclient -v addr GETV "${connReqIf}.IPv6Address.+.[Status=Enabled].[IPAddressStatus!Invalid].IPAddress"
if [ -z "$addr" ]; then
cmclient -v addr GETV "${connReqIf}".IPv4Address.+.IPAddress
for addr in $addr; do
break
done
IPv6Addr=0
else
for single in $addr; do
case $single in
fe80*)
;;
*)
found="y"
break
;;
esac
done
if [ "$found" = "y" ]; then
addr="$single"
IPv6Addr=1
else
cmclient -v addr GETV "${connReqIf}".IPv4Address.+.IPAddress
for addr in $addr; do
break
done
IPv6Addr=0
fi
fi
else
cmclient -v addr GETV "${connReqIf}".IPv4Address.+.IPAddress
for addr in $addr; do
break
done
IPv6Addr=0
fi
if [ -n "$addr" ]; then
cmclient -v _tmp GETV Device.ManagementServer.X_ADB_ConnectionRequestRandomPath
if [ "$_tmp" = "true" ]; then
randPath=$(tr -Cd "a-zA-Z0-9" < /dev/urandom | head -c 10)
newX_ADB_ConnectionRequestPath=$newX_ADB_ConnectionRequestPath$randPath
fi
[ "$IPv6Addr" = "1" ] &&\
newurl="http://[${addr}]:${newX_ADB_ConnectionRequestPort}/${newX_ADB_ConnectionRequestPath}" ||\
newurl="http://${addr}:${newX_ADB_ConnectionRequestPort}/${newX_ADB_ConnectionRequestPath}"
else
newurl=""
fi
[ -n "$newurl" -a "$newurl" != "$newConnectionRequestURL" ] && cmclient -u TR069 SET Device.ManagementServer.ConnectionRequestURL "$newurl"
fi
if [ "$changedEnableCWMP" = "1" ] || [ "$setEnableCWMP" = "1" -a "$user" = "boot" ] || [ "$setEnableCWMP" = "1" -a "$user" = "POSTPROVISIONING" ]; then
if help_post_provisioning_add "Device.ManagementServer.EnableCWMP" "$newEnableCWMP" "Default"; then
if [ "$newEnableCWMP" = "true" ]; then
[ -f "$PIDFILE" ] && help_svc_stop cwmp "$PIDFILE" "15"
[ -f /tmp/CWMP/ca.pem ] || cp /etc/certs/ca.pem /tmp/CWMP/ca.pem
[ -f /tmp/CWMP/cpe-cert.pem ] || cp /etc/certs/cpe-cert.pem /tmp/CWMP/cpe-cert.pem
[ -f /tmp/CWMP/cpe-private-key.pem ] || cp /etc/certs/cpe-private-key.pem /tmp/CWMP/cpe-private-key.pem
help_svc_start cwmp '' '' '' '' '15'
else
cwmpShutdown
fi
fi
fi
[ "$changedURL" = "1" -a "$user" != "PPPAsyncPack" ] && cmclient -u TR069 SETE Device.ManagementServer.X_ADB_EnablePPPURLDiscovery false
[ "$user" = "POSTPROVISIONING" ] && exit 0
if help_is_changed X_ADB_ConnectionRequestPort X_ADB_ConnectionRequestInterface \
EnableCWMP X_ADB_AccessControlEnable X_ADB_AccessControl ||
[ "$setEnableCWMP" = "1" -a "$user" = "boot" ]; then
help_iptables -t nat -F NATSkip_ACS
help_iptables -F CWMPIn
if [ "$changedX_ADB_AccessControlEnable" = "1" ]; then
[ "$newX_ADB_AccessControlEnable" = "true" ] && cmd_line=-A || cmd_line=-D
help_iptables_all $cmd_line ServicesIn_LocalACLServices -j CWMPIn
help_iptables_all $cmd_line OutputAllow_LocalACLServices -j CWMPOut
fi
[ "$newEnableCWMP" = "false" ] && exit 0
reconf_acs_fw "$newX_ADB_ConnectionRequestInterface" "$newX_ADB_ConnectionRequestPort" "$newX_ADB_AccessControl" "$newX_ADB_AccessControlEnable"
[ "$changedX_ADB_ConnectionRequestInterface" = "1" ] && help_reconfigure_nat_conflicts "$oldX_ADB_ConnectionRequestInterface"
exit 0
fi
