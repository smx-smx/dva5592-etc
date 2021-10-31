#!/bin/sh
AH_NAME="Management"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_functions.sh
service_config() {
case "$obj" in
Device.UserInterface)
if [ "$changedPasswordRequired" = "1" ]; then
[ "$newPasswordRequired" = "true" ] && state="enabled" || state="disabled"
logger -t "cm" -p 7 "Access password ${state}"
fi
if [ "$setPasswordReset" = "1" -a "$newPasswordReset" = "true" ]; then
local pwd=""
cmclient -v pwd GETV Device.X_ADB_CustomConf.[ConfigurationSet=CustomConf].Object.[Name="Device.LANConfigSecurity"].**.[Name=ConfigPassword].Value
if [ -n "$pwd" ]; then
cmclient SET Device.LANConfigSecurity.ConfigPassword "$pwd" > /dev/null 
fi
fi
;;
Device.LANConfigSecurity)
[ "$changedConfigPassword" = "1" ] && logger -t "cm" -p 7 "Access password changed"
;;
esac
}
case "$op" in
s)
service_config
;;
esac
exit 0
