#!/bin/sh
. /etc/ah/helper_functions.sh
reset_counters() {
local typ="$1"
cmclient DEL "UserInterface.X_ADB_FailLog.$typ"
}
service_config() {
local typ
case "$obj" in
Device.UserInterface)
if [ "$changedX_ADB_LoginBanner" = "1" ]; then
cmclient SET Device.X_ADB_SSHServer.LocalAccess.[Enable=true].Enable true
cmclient SET Device.X_ADB_SSHServer.RemoteAccess.[Enable=true].Enable true
cmclient SET Device.X_ADB_TelnetServer.LocalAccess.[Enable=true].Enable true
cmclient SET Device.X_ADB_TelnetServer.RemoteAccess.[Enable=true].Enable true
fi
if [ "$changedX_ADB_LockoutType" = "1" ]; then
for typ in "User" "Host"; do
help_is_in_list "$oldX_ADB_LockoutType" "$typ" && \
! help_is_in_list "$newX_ADB_LockoutType" "$typ" && \
reset_counters "$typ"
done
fi
if [ "$changedX_ADB_MaxFailedLoginAttempts" = "1" ]; then
if [ "$oldX_ADB_MaxFailedLoginAttempts" = "0" ]; then
reset_counters "User"
reset_counters "Host"
fi
if [ "$newX_ADB_MaxFailedLoginAttempts" = "0" ]; then
cmclient SET Device.UserInterface.X_ADB_FailLog.User.Locked false
cmclient SET Device.UserInterface.X_ADB_FailLog.Host.Locked false
fi
fi
;;
esac
}
case "$op" in
s)
service_config
;;
esac
exit 0
