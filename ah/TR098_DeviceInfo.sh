#!/bin/sh
AH_NAME="TR098_DeviceInfo"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_get()
{
local obj98="$1"
local param98="$2"
local value98=""
case "$param98" in
"ModemFirmwareVersion")
output=`xdslctl --version 2>&1`
remove="PHY: AnnexA version - "
value98="${output##*"$remove"}"
;;
"UpTime")
uptime=`cut -d' ' -f1 /proc/uptime`
value98="${uptime%.*}"
;;
"DeviceLog")
sysEnb=`cmclient GETV Device.X_ADB_SystemLog.Enable`
if [ "$sysEnb" = "true" ]; then	
logc t 0 32k 0 0 0 \"%Y-%M-%D %H:%m:%s %g %a\" *7
fi
;;
*)
;;
esac
echo "$value98"
}
case "$op" in
"g")
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
;;
esac
exit 0
