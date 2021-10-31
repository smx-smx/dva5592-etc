#!/bin/sh
AH_NAME="PPTP-Client"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tunnel.sh
. /etc/ah/helper_ppp.sh
start_pptp_daemon() {
local cmd_arg_encr="" cmd_arg_auth="" pid_file
getAuthenticationProtocolClientCmd "$newAuthenticationProtocol" "cmd_arg_auth"
[ $? -eq $HELPER_PPP_PROTO_MPPE_RET ] && getEncryptionProtocolCmd "$newX_ADB_EncryptionProtocol" "cmd_arg_encr"
if [ -n "$cmd_arg_auth" ]; then
cmd_arg_auth="$cmd_arg_auth user $newUsername"
cmd_arg_auth="$cmd_arg_auth plugin passwordfd.so password $newPassword"
fi
if [ "$newAutoDisconnectTime" != "0" ] && [ "$newAutoDisconnectTime" != "" ]; then
pptp_cmd_arg_conn="maxconnect $newAutoDisconnectTime"
fi
if [ "$newIdleDisconnectTime" != "0" ] && [ "$newIdleDisconnectTime" != "" ]; then
pptp_cmd_arg_conn="$pptp_cmd_arg_conn idle $newIdleDisconnectTime"
fi
pid_file="/tmp/PPTPClient$obj.pid"
ADB_PPPD_CLOSE_FD=1 \
pppd linkname $newAlias $cmd_arg_encr $cmd_arg_auth $pptp_cmd_arg_conn lldevname lo ifname "$newName" name "Client.PPTP" \
pty "/etc/ah/pptp_wrapper.sh start $pid_file $newHostname --nolaunchpppd linkname $newAlias || true" \
disconnect "/etc/ah/pptp_wrapper.sh stop $pid_file || true" \
persist maxfail 0 &
}
kill_pptp_daemon() {
local host="$1" pid=""
local any_pid_killed=""
read pid < "/var/run/ppp-$newAlias.pid"
if [ -n "$pid" ]; then
kill "$pid"
any_pid_killed="true"
fi
pid=`pgrep -f "pptp: call manager for $newHostName"`
if [ -n "$pid" ]; then
kill $pid
any_pid_killed="true"
fi
pid=`pgrep -f "pptp $newHostName"`
while [ -n "$pid" ]; do
kill $pid
pid=`pgrep -f "pptp $newHostName"`
any_pid_killed="true"
done
if [ -n "$newAlias" ]; then
pid=`pgrep -f "linkname $newAlias"`
while [ -n "$pid" ]; do
kill $pid
pid=`pgrep -f "pptp $newAlias"`
any_pid_killed="true"
done
fi
if [ "$any_pid_killed" = "true" ]; then
local tries=5
local status
cmclient -v status GETV "$obj.LocalIPAddress"
while [ "$status" != "" -a $tries -ne 0 ]; do
sleep 1
cmclient -v status GETV "$obj.LocalIPAddress"
tries=$((tries - 1))
done
fi
}
service_reconf() {
if [ $changedEnable -eq 1 ]; then
if [ "$newEnable" = "false" ]; then
new_status="Disconnected"
kill_pptp_daemon "$newHostname"
else
new_status=""
fi
else
if [ "$newEnable" = "true" ]; then
new_status="$newStatus"
case $new_status in
"Connected" | "Connecting" )
if [ $changedStatus -eq 0 ]; then
kill_pptp_daemon "$newHostname"
new_status=""
fi
;;
"Disconnected" )
new_status=""
;;
* )
kill_pptp_daemon "$newHostname"
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
cmclient -v ipif_status GETV "$newInterface.Status"
[ "$ipif_status" != "Up" ] && new_status="Disconnected"
fi
if [ $changedReset -eq 1 ]; then
if [ "$newReset" = "true" ]; then
kill_pptp_daemon "$newHostname"
new_status=""
fi
fi
if [ -z "$new_status" ]; then
if [ -z "$newHostname" ] || [ -z "$newAuthenticationProtocol" ]; then
new_status="Unconfigured"
elif [ "$newAuthenticationProtocol" != "none" ]; then
[ -z "$newUsername" -o -z "$newPassword" ] && new_status="Unconfigured"
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
if add_tunnel_route "$obj"; then
start_pptp_daemon
new_status="Connecting"
else
new_status="Unconfigured"
fi
fi
[ "$new_status" != "$newStatus" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "$new_status"
}
service_config() {
[ "$changedRemoteIPAddress" = "1" -o "$changedLocalIPAddress" = "1" -o "$changedName" = "1" ] && return
service_reconf
}
service_delete() {
kill_pptp_daemon "$newHostname"
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
