#!/bin/sh
AH_NAME="FTP-Server"
[ "$user" = "yacs" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ -f /tmp/upgrading.lock ] && [ "$op" != "g" ] && exit 0
trim0() {
local val="$1"
while :; do
local _val="${val#0}"
[ "$_val" = "$val" ] && break
val="$_val"
done
[ -z "$val" ] && val="0"
echo -n "$val"
}
needRefresh() {
[ "$setX_ADB_Refresh" = "1" -a "$newX_ADB_Refresh" = "true" ] && return 0
[ "$changedEnable" = "1" ] && return 0
[ "$changedIdleTime" = "1" ] && return 0
[ "$changedMaxNumUsers" = "1" ] && return 0
[ "$changedPortNumber" = "1" ] && return 0
[ "$changedX_ADB_StartingFolder" = "1" ] && return 0
[ "$changedX_ADB_Interfaces" = "1" ] && return 0
return 1
}
kill_ftp_server() {
if [ "$newEnable" = "false" ]; then
rm ${FTP_INETD_FILE} > /dev/null 2>&1
fi
help_iptables -F FTP${FTPPREFIX}In
help_iptables -F FTP${FTPPREFIX}In_
cmclient -u "${AH_NAME}${obj}" SET "${obj}.Status" "Disabled"
}
run_ftp_server() {
local status="Disabled" bindip="" u
kill_ftp_server
[ "$newEnable" = "false" ] && return
help_iptables -F FTP${FTPPREFIX}In
help_iptables -F FTP${FTPPREFIX}In_
help_iptables -N FTP${FTPPREFIX}In_
help_iptables -A FTP${FTPPREFIX}In ! -p tcp -j RETURN
help_iptables -A FTP${FTPPREFIX}In_ -j HELPER --helper "ftp"
help_iptables -A FTP${FTPPREFIX}In_ -j ACCEPT
aobj="$obj.AnonymousUser"
cmclient -v aenable GETV "$aobj.Enable"
cmclient -v onlyanonymous GETV "$aobj.X_ADB_OnlyAnonymousUser"
case "${FTPPREFIX}" in
Remote)
PWFILE="${FTPRemote_PASSWDFILE}"
DBFILE="${FTPRemote_DBFILE}"
accountParameter="X_ADB_AllowRemoteFTPAccess"
;;
Local)
PWFILE="${FTPLocal_PASSWDFILE}"
DBFILE="${FTPLocal_DBFILE}"
accountParameter="AllowFTPAccess"
;;
esac
otherPort="`trim0 $otherPort`"
if [ ! -f "$DBFILE" -o ! -f "$PWFILE" ]; then
touch "$DBFILE"
touch "$PWFILE"
pobj=${obj%.*}
cmclient -v u GETO $pobj.UserAccount.[Enable=true].[$accountParameter=true]
for u in $u; do
cmclient SET $u.X_ADB_AllowFTPAccessRefresh true
done
pure-pw mkdb "$DBFILE" -f "$PWFILE"
fi
user="-l puredb:$DBFILE"
if [ "$aenable" = "true" ]; then
env op="refresh" obj="$aobj" /etc/ah/FTP-Server-Anonymous.sh
cmclient -v anonymReadOnlyAccess GETV "$aobj.ReadOnlyAccess"
if [ "$anonymReadOnlyAccess" = "true" ]; then
user="$user -i"
else
user="$user -M"
fi
fi
if [ "$aenable" = "false" ]; then
user="$user -E"
elif [ "$aenable" = "true" -a "$onlyanonymous" = "true" ]; then
user="$user -e"
fi
[ -z "$newPortNumber" -o "$newPortNumber" = "0" ] && newPortNumber=21
[ -z "$newMaxNumUsers" ] && newMaxNumUsers=32
[ -z "$newIdleTime" ] && newIdleTime=0
if [ "$newIdleTime" != "0" ]; then
ftpIdleTimeInMin=$(($(($newIdleTime + 59)) / 60))
[ $ftpIdleTimeInMin -eq 0 ] && ftpIdleTimeInMin=1
else
ftpIdleTimeInMin=$FTP_MAX_TIMEOUT
fi
prefixCmdLine="-A"
postfixCmdLine="-I $ftpIdleTimeInMin -c $newMaxNumUsers"
if [ -z "$newX_ADB_Interfaces" ]; then
case "${FTPPREFIX}" in
Remote)
cmclient -v newX_ADB_Interfaces GETO "Device.IP.Interface.[X_ADB_Upstream=true].[Status=Up]"
;;
Local)
cmclient -v newX_ADB_Interfaces GETO "Device.IP.Interface.[X_ADB_Upstream=false].[Status=Up]"
;;
esac
fi
if [ "$newEnable" = "true" ]; then
cmd_line="pure-ftpd -7 $FTPUSER -H -g $prefixCmdLine $user $postfixCmdLine"
help_iptables -A FTP${FTPPREFIX}In -p tcp ! --dport ${newPortNumber} -j RETURN
IFS=', 
'
set -f
rm -f $FTP_INETD_FILE
for ipObj in $newX_ADB_Interfaces; do
local ifenable ifname
cmclient -v ifenable GETV $ipObj.Status
if [ "$ifenable" = "Up" ]; then
help_lowlayer_ifname_get ifname "$ipObj"
if [ -n "$ifname" ]; then
help_iptables -A FTP${FTPPREFIX}In -i ${ifname} -j FTP${FTPPREFIX}In_
cmclient -v bindip GETV "$ipObj.IPv4Address.[Enable=true].IPAddress"
for bindip in $bindip; do
echo "$bindip,ftp,$newPortNumber stream tcp nowait root `which pure-ftpd` $cmd_line" >> $FTP_INETD_FILE
done
fi
status="Enabled"
fi
done
unset IFS
set +f
fi
cmclient -u "${AH_NAME}${obj}" SET "${obj}.Status" "$status"
}
service_config() {
if needRefresh; then
if [ "$newEnable" = "true" ]; then
if help_is_changed Enable PortNumber X_ADB_Interfaces; then
. /etc/ah/helper_conflicts.sh
local remote
[ "$FTPPREFIX" = "Remote" ] && remote=1 || remote=0
help_check_conflicts "$remote" "$newX_ADB_Interfaces" "$newPortNumber" || exit 1
fi
run_ftp_server
else
kill_ftp_server
fi
fi
}
refresh_ipif() {
local ipobj="$1" refreshremote=0 refreshlocal=0 tmp
[ "$changedStatus" = "1" ] || exit 0
cmclient -v tmp GETV Device.Services.StorageService.1.FTPServer.X_ADB_Interfaces
if [ ${#tmp} -eq 0 ]; then
case ,"$tmp", in *,"$ipobj",* ) refreshlocal=1 ;; esac
else
cmclient -v tmp GETV $ipobj.X_ADB_Upstream
[ "$tmp" = "false" ] && refreshlocal=1
fi
cmclient -v tmp GETV Device.Services.StorageService.1.X_ADB_FTPServerRemote.X_ADB_Interfaces
if [ ${#tmp} -eq 0 ]; then
case ,"$tmp", in *,"$ipobj",* ) refreshremote=1 ;; esac
else
cmclient -v tmp GETV $ipobj.X_ADB_Upstream
[ "$tmp" = "true" ] && refreshremote=1
fi
[ "$refreshlocal" = "1" ] && cmclient SET Device.Services.StorageService.1.FTPServer.X_ADB_Refresh true &
[ "$refreshremote" = "1" ] && cmclient SET Device.Services.StorageService.1.X_ADB_FTPServerRemote.X_ADB_Refresh true &
}
case "$op" in
s)
case "$obj" in
Device.Services.StorageService.*.FTPServer | Device.Services.StorageService.*.X_ADB_FTPServerRemote )
. /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/FTP-Server-Common.sh
service_config
;;
Device.Services.StorageService.*.*.AnonymousUser)
cmclient SET ${obj%.AnonymousUser}.X_ADB_Refresh true
;;
Device.IP.Interface.*.IPv4Address.*)
ipobj="${obj%.IPv4Address.*}"
refresh_ipif "$ipobj" &
;;
Device.IP.Interface.*)
refresh_ipif "$obj" &
;;
esac
;;
esac
exit 0
