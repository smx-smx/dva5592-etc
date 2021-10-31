#!/bin/sh
[ "$op" != "g" -o "$1" != "CallTerminationCause" ] && exit 0
case "$newCallTerminationCause" in
X_ADB_*)
[ "$user" = "CWMP" ] && printf "%s\n" "X_DLINK_${newCallTerminationCause#X_ADB_}" && exit 0
;;
*)
;;
esac
printf "${newCallTerminationCause}\n"
exit 0
