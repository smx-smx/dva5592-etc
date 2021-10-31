#!/bin/sh
AH_NAME="PPPIf"
EH_NAME="PPPLink"
EH_AUTH_NAME="PPPAuthFail"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
if [ "$op" = "s" -a "$changedIPv6CPEnable" = "1" -a "$newIPv6CPEnable" = "false" ]; then
cmclient -v ipv6_global GETV "Device.IP.IPv6Enable"
if [ "$ipv6_global" = "true" ]; then
[ -n "$newConnectionStatus" ] && ConnectionStatus="$newConnectionStatus" || cmclient -v ConnectionStatus GETV $obj.ConnectionStatus
if [ "$ConnectionStatus" = "Connected" ]; then
. /etc/ah/helper_ifname.sh
help_lowlayer_ifname_get ifname $obj
logger -t "cm" "PPP Interface $ifname: IPv6: Down" -p 6
fi
fi
fi
[ "$user" = "$EH_NAME" ] && exit 0
[ "$user" = "$EH_AUTH_NAME" ] && exit 0
[ "$user" = "InterfaceMonitor" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_status.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_lastChange.sh
. /etc/ah/helper_provisioning.sh
. /etc/ah/helper_ppp.sh
PPP_PAP_SECRETS="/tmp/ppp/pap-secrets"
PPP_CHAP_SECRETS="/tmp/ppp/chap-secrets"
PPP_PAP_CHAP_UA="/tmp/ppp/pap-chap-ua${obj##*.}"
WWAN_CONFIG="/tmp/wwan-chat.conf"
NEWLINE='
'
object=""
ppp_usr=""
ppp_psw=""
ppp_auth=""
ppp_link_name=""
ppp_auth_changed="0"
ppp_passwd_valid="0"
ppp_usr_valid="0"
ppp_connectionTrigger=""
pppd_cmd="pppd usepeerdns"
pppd_ifname="/dev/ttyS0"
pppConfigStart() {
if ! help_post_provisioning_add "$obj.Reset" "true" "Default"; then
exit 0
fi
ppp_config_start "Down"
PRI_update_status "$obj" "" "$newStatus" "ignore_ConnTrigg" "force"
exit 0
}
pppConfigRefresh() {
PRI_ppp_auth_file_update
help_check_cwmp_progress
help_serialize "ah_${AH_NAME}${obj}_PPPRefresh"
ppp_refresh_daemon "$obj"
exit 0
}
pppPrepare() {
[ $is_ppp_usb_dongle -eq 1 ] && [ -f /etc/ah/helper_wwan.sh ] \
&& . /etc/ah/helper_wwan.sh && help_wwan_prepare
}
needRestart() {
[ "$user" = "${AH_NAME}${obj}" ] && return 1
[ "$changedConnectionTrigger" = "1" ] && return 0
[ "$changedPassword" = "1" ] && return 0
if [ "$changedUsername" = "1" ]; then
[ -f /etc/ah/helper_check_custom_if_cond.sh ] && . /etc/ah/helper_check_custom_if_cond.sh && help_set_ppp_userchanged_flag "$obj"
return 0
fi
[ "$setReset" = "1" -a "$newReset" = "true" ] && return 0
[ "$changedX_ADB_RequestMask" = "1" ] && return 0
return 1
}
needRefresh() {
[ "$user" = "${AH_NAME}${obj}" ] && return 1
[ "$changedPassword" = "1" ] && return 0
[ "$changedUsername" = "1" ] && return 0
return 1
}
store_PADT() {
local object="$1" pppoe_data_file="$2"
cmclient -v pppoe_session GETV $object.PPPoE.SessionID
pppoe_session=`printf "%0.4X" $pppoe_session`
echo "$pppoe_session" > $pppoe_data_file
cmclient -v pppoe_devname GETV $object.PPPoE.X_ADB_DeviceName
echo "$pppoe_devname" >> $pppoe_data_file
cmclient -v pppoe_localmac GETV $object.PPPoE.X_ADB_LocalMACAddress
echo "$pppoe_localmac" >> $pppoe_data_file
cmclient -v pppoe_remotemac GETV $object.PPPoE.X_ADB_RemoteMACAddress
echo "$pppoe_remotemac" >> $pppoe_data_file
}
send_PADT() {
local pppoe_data_file="$1"
if [ ${#pppoe_data_file} -eq 0 ]; then
cmclient -v pppoe_session GETV "$obj.PPPoE.SessionID"
pppoe_session=`printf "%0.4X" $pppoe_session`
cmclient -v interface GETV "$obj.PPPoE.X_ADB_DeviceName"
cmclient -v local_mac GETV "$obj.PPPoE.X_ADB_LocalMACAddress"
cmclient -v remote_mac GETV "$obj.PPPoE.X_ADB_RemoteMACAddress"
elif [ -f $pppoe_data_file ]; then
pppoe_session=`head -n 1 $pppoe_data_file`
interface=`tail -n 3 $pppoe_data_file | head -n 1`
local_mac=`tail -n 2 $pppoe_data_file | head -n 1`
remote_mac=`tail -n 1 $pppoe_data_file`
fi ###
if [ ${#pppoe_session} -eq 0  -o "$pppoe_session" = "0000" ]; then
echo "### $AH_NAME: no PADT - SESSION info unavailable ###"
return
fi
if [ ${#interface} -eq 0 ]; then
echo "### $AH_NAME: no PADT - DEVICE info unavailable ###"
return
fi
if [ ${#local_mac} -eq 0 ]; then
echo "### $AH_NAME: no PADT - LOCAL MAC unavailable ###"
return
fi
if [ ${#remote_mac} -eq 0 ]; then
echo "### $AH_NAME: no PADT - REMOTE MAC unavailable ###"
return
fi
local_mac=`help_tr ":" "" "$local_mac"`
remote_mac=`help_tr ":" "" "$remote_mac"`
echo "### $AH_NAME: sending PADT - session [$pppoe_session] -> $interface ###"
padt_gen "$remote_mac" "$local_mac" "$pppoe_session" "$interface" "GEN_ERROR" "PPP daemon terminated."
}
PRI_fill_param_connection() {
local acname active_filter servicename ipObj prioClass tcProto
ppp_cmd_arg_conn=""
active_filter="/etc/ppp/filter_ipv4"
cmclient -v ipv6_global GETV Device.IP.IPv6Enable
if [ "$ipv6_global" = "true" -a "$newIPv6CPEnable" = "true" ]; then
ppp_cmd_arg_conn="$ppp_cmd_arg_conn +ipv6"
active_filter="/etc/ppp/filter_ipv6"
fi
ppp_cmd_arg_conn="$ppp_cmd_arg_conn precompiled-active-filter $active_filter"
[ ${#obj} -ne 0 ] && ppp_cmd_arg_conn="$ppp_cmd_arg_conn linkname ${obj}"
if [ "$newConnectionTrigger" != "AlwaysOn" ]; then
cmclient -v ipObj GETO "Device.IP.Interface.[LowerLayers=$obj]"
if [ "$newConnectionTrigger" = "OnDemand" ] || [ "$newConnectionTrigger" = "X_ADB_OnClient" ]
then
ppp_cmd_arg_conn="$ppp_cmd_arg_conn demand"
if [ ${#ipObj} -ne 0 ]; then
cmclient -v monObj GETO "Device.X_ADB_InterfaceMonitor.[Enable=true].Group.[Enable=true].Interface.[MonitoredInterface=$ipObj].[Enable=true]"
if [ ${#monObj} -ne 0 ]; then
_defroute="true"
else
cmclient -v _defroute GETV "$ipObj.X_ADB_DefaultRoute"
fi
fi
[ "$_defroute" = "true" ] && ppp_cmd_arg_conn="$ppp_cmd_arg_conn defaultroute"
fi
[ ${#newAutoDisconnectTime} -ne 0 ] && [ "$newAutoDisconnectTime" != "0" ] \
&& ppp_cmd_arg_conn="$ppp_cmd_arg_conn maxconnect $newAutoDisconnectTime"
[ ${#newIdleDisconnectTime} -ne 0 ] && [ "$newIdleDisconnectTime" != "0" ] \
&& ppp_cmd_arg_conn="$ppp_cmd_arg_conn idle $newIdleDisconnectTime"
else	###--- ALWAYS ON -----------------------###
ppp_cmd_arg_conn="$ppp_cmd_arg_conn persist"
fi
cmclient -v acname GETV "$obj.PPPoE.ACName"
cmclient -v servicename GETV "$obj.PPPoE.ServiceName"
[ ${#acname} -ne 0  ] && ppp_cmd_arg_conn="${ppp_cmd_arg_conn} rp_pppoe_ac ${acname}"
[ ${#servicename} -ne 0 ] && ppp_cmd_arg_conn="${ppp_cmd_arg_conn} rp_pppoe_service ${servicename}"
cmclient -v prioClass GETV Device.QoS.X_ADB_DefaultClassification.[Enable=true].TrafficClass
if [ -n "$prioClass" ]; then
cmclient -v tcProto GETV Device.QoS.X_ADB_DefaultClassification.Protocols
[ -n "$tcProto" ] && help_is_in_list "$tcProto" "PPPoE" && ppp_cmd_arg_conn="${ppp_cmd_arg_conn} lcpmark $((prioClass*16777216))"
fi
}
PRI_fill_param_authentication() {
ppp_cmd_arg_encr=""
getAuthenticationProtocolClientCmd "$newAuthenticationProtocol" "ppp_cmd_arg_auth"
[ $? -eq $HELPER_PPP_PROTO_MPPE_RET ] && getEncryptionProtocolCmd "$newX_ADB_EncryptionProtocol" "ppp_cmd_arg_encr"
ppp_cmd_arg_auth="$ppp_cmd_arg_auth noauth"
[ -x /etc/ah/ti_ppp_uname.sh ] && . /etc/ah/ti_ppp_uname.sh
if [ ${#newUsername} -ne 0 -a ${#newPassword} -ne 0 ]; then
PRI_ppp_auth_file_update
else
: > "$PPP_PAP_CHAP_UA"
fi
ppp_cmd_arg_auth="$ppp_cmd_arg_auth +ua $PPP_PAP_CHAP_UA"
}
PRI_fill_param_compproto() {
[ "$newCompressionProtocol" = "None" ] && ppp_cmd_arg_comp="novj"
case "$newX_ADB_PayloadCompressionProtocolMaxCodeSize" in
"Deflate")
ppp_cmd_arg_comp="$ppp_cmd_arg_comp deflate $newX_ADB_PayloadCompressionProtocolMaxCodeSize"
;;
"BSD")
ppp_cmd_arg_comp="$ppp_cmd_arg_comp bsdcomp $newX_ADB_PayloadCompressionProtocolMaxCodeSize"
;;
*)
;;
esac
}
PRI_fill_param_holdoff() {
ppp_cmd_holdoff=""
}
PRI_fill_param_timing() {
local auto ip_obj mtu
. /etc/ah/helper_mtu.sh
cmclient -v ip_obj GETV "Device.InterfaceStack.[LowerLayer=$obj].HigherLayer"
cmclient -v auto GETV $ip_obj.X_ADB_AutoMTU
if [ "$auto" = true ]; then
help_get_default_mtu mtu "$obj"
else
cmclient -v mtu GETV $ip_obj.MaxMTUSize
help_lowlayer_set_mtu $obj $mtu
fi
[ ${newMaxMRUSize:-65536} -lt ${mtu:-65536} ] && mtu=$newMaxMRUSize
[ ${#mtu} -gt 0 ] && ppp_cmd_arg_time="mru $mtu mtu $mtu"
[ ${#newLCPEchoRetry} -eq 0 ] && newLCPEchoRetry="5"
[ ${#newLCPEcho} -eq 0 ] && newLCPEcho="15"
echoRetry=$((newLCPEchoRetry+1))
echoFailure=$((newLCPEcho/echoRetry))
ppp_cmd_arg_time="$ppp_cmd_arg_time lcp-echo-failure $newLCPEchoRetry"
ppp_cmd_arg_time="$ppp_cmd_arg_time lcp-echo-interval $echoFailure"
[ ${#newX_ADB_CHAPInterval} -ne 0 ] && ppp_cmd_arg_time="$ppp_cmd_arg_time chap-interval $newX_ADB_CHAPInterval"
}
PRI_fill_param_wwan() {
local simcard apn apn_url apn_dial apn_user apn_pwd
cmclient -v low_ifname GETV "$newLowerLayers.Modem.DataDevice"
cmclient -v simcard GETV "$newLowerLayers.ActiveSIMCard"
cmclient -v apn GETV "$simcard.PreferredAPN"
cmclient -v apn_url GETV "$apn.URL"
cmclient -v apn_dial GETV "$apn.Dial"
cmclient -v apn_user GETV "$apn.Username"
cmclient -v apn_pwd GETV "$apn.Password"
if [ -s $WWAN_CONFIG ]; then
echo "### $AH_NAME: wwan - file config found ###"
ppp_cmd_arg_connect="-f $WWAN_CONFIG"
else
echo "### $AH_NAME: wwan - file config not found ###"
ppp_cmd_arg_connect="-s ABORT BUSY ABORT \"NO CARRIER\" ABORT ERROR REPORT CONNECT TIMEOUT 10 \"\" ATZ OK \"AT+CGDCONT=1,\\\\042IP\\\\042,\\\\042$apn_url\\\\042\" OK \"ATD $apn_dial\" CONNECT \\\\c"
fi
is_ppp_usb_dongle=1
ppp_cmd_arg_auth="noauth user $apn_user password $apn_pwd"
}
PRI_find_low_ifname() {
local atm_addr="" atm_vpi="" atm_vci="" t=0
help_lowlayer_ifname_get low_ifname "$newLowerLayers" "$newX_ADB_ActiveLowerLayer"
if [ ${#low_ifname} -eq 0 ]; then
echo "### $AH_NAME: ERROR - Physical interface not found ###"
exit 2
fi
real_low_ifname=$low_ifname
case "$low_ifname" in
"usb"* )
PRI_fill_param_wwan		# ppp_cmd_arg_connect
real_low_ifname="lo"
;;
* )
while [ ! -d /sys/class/net/"$low_ifname" ]; do
[ $t -lt 60 ] && sleep 1 || break
t=$((t+1))
cmclient -v newX_ADB_ActiveLowerLayer GETV "$obj.X_ADB_ActiveLowerLayer"
help_lowlayer_ifname_get low_ifname "$newLowerLayers" "$newX_ADB_ActiveLowerLayer"
done
help_if_link_change "$low_ifname" "Up" "$AH_NAME"
case "$newX_ADB_ActiveLowerLayer" in
Device.ATM.Link.*)
delayed_cmd="eval sleep 0.2; echo \"pppoa $low_ifname $newName 0 \" > /proc/net/yatta/vdevs"
cmclient -v atm_addr GETV "$newX_ADB_ActiveLowerLayer.DestinationAddress"
atm_vpi="${atm_addr%%"/"*}"
atm_vci="${atm_addr##*"/"}"
low_ifname=$atm_vpi"."$atm_vci
;;
esac
;;
esac
}
PRI_ppp_auth_file_update() {
local filename=""
echo "$newUsername" > "$PPP_PAP_CHAP_UA"
echo "$newPassword" >> "$PPP_PAP_CHAP_UA"
case "$newAuthenticationProtocol" in
"PAP")
filename="/tmp/ppp/pap-secrets"
;;
"CHAP")
filename="/tmp/ppp/chap-secrets"
;;
*) # No file update needed
return
;;
esac
cat "$filename" | grep -v "$oldUsername * $oldPassword *" > "$filename"
echo "$newUsername * $newPassword *" >> "$filename"
}
check_proc_pid() {
local pid="$1" pname="$2" rdpname=''
read -r _ rdpname _ < "/proc/$pid/stat"
[ -z "$rdpname" ] && return 1
rdpname=${rdpname#(}
rdpname=${rdpname%)}
[ "$rdpname" != "$pname" ] && return 1
return 0
}
PRI_update_status() {
local _obj="$1" _obj_enable="$2" _obj_status="$3" _obj_conntrig="$4" _force="$5" next_status=""
if [ "$_obj_conntrig" = "Manual" ]; then
next_status="LowerLayerDown"
else
help_get_status_from_lowerlayers next_status $obj
fi
if [ "$next_status" != "$_obj_status" -o ${#_force} -ne 0 ]; then
cmclient -u "${AH_NAME}${_obj}" SET "${_obj}.Status" "$next_status"
ppp_config_start "$next_status" &
fi
}
PRI_fill_param_ipcp() {
local req_mask
cmclient -v req_mask GETV "$obj.X_ADB_RequestMask"
[ "$req_mask" = "true" ] && ppp_cmd_arg_ipcp="reqmask"
}
PRI_manage_ondemand() {
local ppplinkname route dentries ifx ip_obj dev dst gw
while sleep 1; do
[ -s "/var/run/ppp-${obj}.pid" ] && grep -q ppp "/var/run/ppp-${obj}.pid" && break
done
ppplinkname=`grep ppp "/var/run/ppp-${obj}.pid"`
if [ ${#ppplinkname} -ne 0 ]; then
[ "$newX_ADB_IgnoreIdleTimeOut" = "true" ] && kill -XCPU `grep -v ppp /var/run/ppp-${obj}.pid`
cmclient -v ip_obj GETV "Device.InterfaceStack.[LowerLayer=$obj].HigherLayer"
. /etc/ah/helper_ipcalc.sh
while read -r dev dst gw _; do
[ "$dev" = "$ppplinkname" -a "$gw" = "00000000" ] || continue
help_int2ip route $((0x$dst))
break
done < /proc/net/route
if [ ${#route} -ne 0 ]; then
cmclient -v dentries GETV "Device.DNS.Relay.X_ADB_DynamicForwardingRule.[Enable=true].[Interface=$ip_obj].X_ADB_InboundInterface"
if [ ${#dentries} -eq 0 ]; then
echo "5 * ${route} 10000 * ${ppplinkname}" > /tmp/dns/ppp_on_demand_${obj}
else
for dentry in $dentries; do
help_lowlayer_ifname_get ifx "$dentry"
if [ ${#ifx} -ne 0 ]; then
echo "5 * ${route} 10000 ${ifx} ${ppplinkname}" > /tmp/dns/ppp_on_demand_${obj}.${dentry}
fi
done
fi
fi
fi
}
ppp_config_start() {
local _status="$1" lock=/tmp/ppp/$obj.delay I=0
local _count _gprs_status _gsm_status _modem_obj
_defroute="false"	# global
help_serialize "ah_${AH_NAME}${obj}_PPPRestart"
while [ $I -lt 26 ]; do
[ ! -f $lock ] && break
sleep 0.2
I=$((I+1))
done
case "$_status" in
"Up")
ppp_cmd_arg_conn=""	# global
ppp_cmd_arg_auth=""
ppp_cmd_arg_encr=""
ppp_cmd_arg_comp=""
ppp_cmd_arg_time=""
ppp_cmd_arg_connect=""
ppp_cmd_arg_ipcp=""
is_ppp_usb_dongle=0
[ -f /etc/ah/helper_check_custom_if_cond.sh ] && . /etc/ah/helper_check_custom_if_cond.sh && help_check_custom_ppp_conditions "$obj" && exit 0
PRI_fill_param_connection	# ppp_cmd_arg_conn
PRI_fill_param_authentication	# ppp_cmd_arg_auth
PRI_fill_param_compproto	# ppp_cmd_arg_comp
PRI_fill_param_timing		# ppp_cmd_arg_time
PRI_fill_param_holdoff		# ppp_cmd_holdoff
PRI_fill_param_ipcp		# ppp_cmd_arg_ipcp
PRI_find_low_ifname
while [ -f "/tmp/$obj.ConnectionStatus" ]; do
echo "### $AH_NAME: WARNING - blocked by check [01], please report it"
sleep 1
done ### ???
ppp_kill_daemon "${obj}"
send_PADT
[ -f /etc/ah/helper_check_custom_if_cond.sh ] && . /etc/ah/helper_check_custom_if_cond.sh && help_ppp_username_changed "$obj"
cmclient SETE "$obj.ConnectionStatus" "Connecting"
echo "### $AH_NAME: Executing ppp daemon:"
echo -n "    <$pppd_cmd"
echo -n " $ppp_cmd_arg_conn $low_ifname $real_low_ifname"
echo -n " $ppp_cmd_arg_auth"
echo -n " $ppp_cmd_arg_encr"
echo -n " $ppp_cmd_arg_comp"
echo -n " $ppp_cmd_arg_time"
echo -n " $ppp_cmd_holdoff"
echo " connect -v \"$ppp_cmd_arg_connect\">"
touch $lock
cmclient -v _modem_obj GETO PPP.Interface.[LowerLayers=Device.X_ADB_MobileModem.Interface.1]
if [ "$_modem_obj" = "$obj" ]; then
_count=0
while [ $_count -lt 10 ]; do
cmclient -v _gsm_status GETV Device.X_ADB_MobileModem.Interface.1.Modem.GSMNetworkRegistered
cmclient -v _gprs_status GETV Device.X_ADB_MobileModem.Interface.1.Modem.GPRSNetworkAttached
[ "$_gsm_status" = "true" -a "$_gprs_status" = "true" ] && break
sleep 1
_count=$(($_count+1))
done
fi
pppPrepare
(	[ -n "$ppp_cmd_arg_connect" ] \
&& $pppd_cmd $ppp_cmd_arg_ipcp $ppp_cmd_arg_conn lldevname $real_low_ifname $low_ifname $ppp_cmd_arg_auth $ppp_cmd_arg_comp \
$ppp_cmd_arg_time $ppp_cmd_holdoff connect "chat -v $ppp_cmd_arg_connect" unit ${newName#ppp} \
|| $pppd_cmd $ppp_cmd_arg_ipcp $ppp_cmd_arg_conn lldevname $real_low_ifname $low_ifname $ppp_cmd_arg_auth $ppp_cmd_arg_comp \
$ppp_cmd_arg_time $ppp_cmd_holdoff unit ${newName#ppp}
rm -f $lock; $delayed_cmd
) &
if [ "$newConnectionTrigger" = "OnDemand" ] || [ "$newConnectionTrigger" = "X_ADB_OnClient" ]; then
PRI_manage_ondemand
fi
;;
*)
[ "$_status" = "LowerLayerDown" -o "$_status" = "Error" ] && I=2 || I=""
ppp_kill_daemon "${obj}" $I
send_PADT
rm -f /tmp/dns/ppp_on_demand_${obj}
rm -f /tmp/dns/ppp_on_demand_${obj}.*
cmclient -u "${AH_NAME}${obj}" SET "$obj.ConnectionStatus" "Disconnected"
;;
esac
}
ppp_ipcp_reconf() {
local path="$1"
if [ "$changedPassthroughDHCPPool" = "1" -o "$changedPassthroughEnable" = "1" ] \
&& [ -n "$newPassthroughDHCPPool" -a "$newPassthroughEnable" = "true" -a -n "$newLocalIPAddress" ]; then
cmclient -v ifname GETV "$path.Name"
subnet_temp=`ifconfig "$ifname" 2>/dev/null`
subnet_temp="${subnet_temp##*Mask:}"
subnet_mask="${subnet_temp%%$NEWLINE*}"
dhcpObj="$newPassthroughDHCPPool"
cmclient -v dhcpEnable GETV "$dhcpObj.Enable"
setm_params="$dhcpObj.MinAddress=$newLocalIPAddress"
setm_params="$setm_params	$dhcpObj.MaxAddress=$newLocalIPAddress"
setm_params="$setm_params	$dhcpObj.SubnetMask=$subnet_mask"
setm_params="$setm_params	$dhcpObj.DNSServers=$newDNSServers"
setm_params="$setm_params	$dhcpObj.Enable=$dhcpEnable"
echo "### $AH_NAME: SET <$dhcpObj.MinAddress> <$newLocalIPAddress> ###"
echo "### $AH_NAME: SET <$dhcpObj.MaxAddress> <$newLocalIPAddress> ###"
echo "### $AH_NAME: SET <$dhcpObj.SubnetMask> <$subnet_mask> ###"
echo "### $AH_NAME: SET <$dhcpObj.DNSServers> <$newDNSServers> ###"
echo "### $AH_NAME: SET <$dhcpObj.Enable> <$dhcpEnable> ###"
cmclient SETM "$setm_params"
fi
}
ppp_kill_daemon() {
local pppPIDFile="/var/run/ppp-${1}.pid" to_delete="$2" ppp_pid ppp_if i=0
if [ -f "$pppPIDFile" ]; then
while :; do
read ppp_pid
read ppp_if
break
done < $pppPIDFile
if [ ${#ppp_pid} -ne 0 ]; then
if ! check_proc_pid "$ppp_pid" 'pppd'; then
ppp_pid=''
rm -f "$pppPIDFile"
fi
fi
if [ ${#ppp_pid} -ne 0 ]; then
[ "$to_delete" = "1" ] && to_delete="-9"
[ "$to_delete" = "2" ] && to_delete="-QUIT"
[ "$to_delete" != "-QUIT" ] && help_serialize "$1" notrap
echo "### $AH_NAME: Executing <kill $to_delete "$ppp_pid"> ###"
kill $to_delete $ppp_pid
[ "$to_delete" != "-QUIT" ] && help_serialize_unlock "$1"
fi
fi
if [ ${#ppp_if} -ne 0 ]; then
while [ -e /sys/class/net/$ppp_if -a $i -lt 16 ]; do
sleep 1
i=$((i+1))
done
fi
}
ppp_refresh_daemon() {
local pppalias="/var/run/ppp-${1}.pid" ppp_pid
if [ -f "$pppalias" ]; then
while :; do
read ppp_pid
read ppp_if
break
done < $pppalias
if [ -n "$ppp_pid" ]; then
echo "### $AH_NAME: Executing <kill -SIGHUP "$ppp_pid"> ###"
kill -SIGHUP $ppp_pid
fi
fi
}
service_delete() {
case "$obj" in
*"PPPoE"*)
object="${obj%%.PPPoE*}"
store_PADT $object /tmp/run/pppoe_session_$object
;;
*"IPCP"*)
;;
*)
ppp_kill_daemon "${obj}" "1"
send_PADT /tmp/run/pppoe_session_$obj	### Send stored PADT
;;
esac
}
service_get() {
local get_path="$1" buf="0" object ifname curr_status
case "$obj" in
*"Stats" )
IGDpath=${obj%%.WANDevice*}
if [ "$IGDpath" = "InternetGatewayDevice" ]; then
nobj=${obj%%.Stats}
cmclient -v obj GETV "$nobj.X_ADB_TR181Name"
fi
object="${obj%%.Stats}"
cmclient -v ifname GETV "$object.Name"
;;
*"PPPoE" )
object="${obj%%.PPPoE}"
cmclient -v curr_status GETV "$object.ConnectionStatus"
[ "$curr_status" = "Connected" ] && cmclient -v ifname GETV "$object.Name"
;;
* )
object="${obj}"
cmclient -v ifname GETV "$object.Name"
;;
esac
if [ -n "$ifname" ]; then
case "$get_path" in
*"CurrentMRUSize" )
[ -f /sys/class/net/$ifname/mtu ] && \
read buf < /sys/class/net/$ifname/mtu
echo $buf
;;
*LastConnectionError )
buf="ERROR_NONE"
[ -e /tmp/ppp/$obj-lastconnerr ] && \
read buf < /tmp/ppp/$obj-lastconnerr
echo $buf
;;
*LastChange)
help_lastChange_get "$obj"
;;
* )
help_get_base_stats "$get_path" "$ifname"
;;
esac
else
echo ""
fi
}
service_config() {
case "$obj" in
Device.PPP.Interface.*.Stats)
local pppIfname parentObj
if [ "$setX_ADB_Reset" = "1" -a "$newX_ADB_Reset" = "true" ]; then
parentObj=${obj%.Stats}
cmclient -v pppIfName GETV $parentObj.Name
[ -n "$pppIfName" -a -d /sys/class/net/"$pppIfName" ] && \
echo $pppIfName > /proc/net/reset_stats
fi
;;
"Device.PPP.Interface."*".IPCP"*)
ppp_ipcp_reconf "${obj%%.IPCP*}"
;;
"Device.PPP.Interface."*".PPPoE"*)
local pppObj="${obj%%.PPPoE}"
if needRestart; then
cmclient SET $pppObj.Reset true
fi
;;
"Device.PPP.Interface."*)
[ "$changedStatus" = 1 ] && help_lastChange_set "$obj"
if [ "$user" = "InterfaceStack" -a "$setEnable" = "1" ]; then
PRI_update_status "$obj" "" "$newStatus" "$newConnectionTrigger"
fi
if [ "$setX_ADB_Reconnect" = "1" -a "$newX_ADB_Reconnect" = "true" ]; then
[ -s /var/run/ppp-${obj}.pid ] && kill -ALRM `grep -v ppp /var/run/ppp-${obj}.pid`
return
fi
if [ "$setX_ADB_Disconnect" = "1" -a "$newX_ADB_Disconnect" = "true" ]; then
[ -s /var/run/ppp-${obj}.pid ] && kill -HUP `grep -v ppp /var/run/ppp-${obj}.pid`
return
fi
if [ "$changedX_ADB_IgnoreIdleTimeOut" = "1" ]; then
[ -s /var/run/ppp-${obj}.pid ] && kill -XCPU `grep -v ppp /var/run/ppp-${obj}.pid`
return
fi
if [ $changedX_ADB_EncryptionProtocol -eq 1 ]; then
if [ "$newX_ADB_EncryptionProtocol" = "None" ]; then
cmclient SETE "$obj.EncryptionProtocol" "None"
else
cmclient SETE "$obj.EncryptionProtocol" "MPPE"
fi
fi
if [ "$changedStatus" = "1" ]; then
if [ "$fo_enable" = "true" ]; then
next_status="$fo_next_status"
if [ "$user" != "Time" ]; then
if [ "$next_status" = "Up" ] || ( [ "$next_status" = "Dormant" ] && [ "$oldStatus" = "Up" ] && [ "$fo_ip_status" = "Up" ] ); then
arm_timer "${obj}" "$next_status"
return
fi
fi
cmclient -u "${AH_NAME}${obj}" SET "${obj}.Status" "$next_status"
ppp_config_start "$next_status"
return
fi
ppp_config_start "$newStatus"
return
fi #---###
if [ "$changedX_ADB_UserEnable" = "1" -a "$newEnable" = "true" ]; then
PRI_update_status "$obj" "$newX_ADB_UserEnable" "$newStatus" "ignore_ConnTrigg" "force"
return
fi
if [ "$changedEnable" = "1" ]; then
[ "$newX_ADB_UserEnable" = "true" ] && PRI_update_status "$obj" "" "$newStatus" "ignore_ConnTrigg"
return
fi
if needRestart; then
[ "$newEnable" = "true" ] && pppConfigStart
fi
;;
esac
}
case "$op" in
d)
service_delete
;;
g)
for arg # Arg list as separate words
do
service_get "$obj.$arg"
done
;;
s)
service_config
;;
esac
exit 0
