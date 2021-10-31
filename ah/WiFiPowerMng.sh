#!/bin/sh
AH_NAME="WiFiPowerMng"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
. /etc/ah/helper_wlan.sh
. /etc/ah/helper_PowerMng.sh
check_status (){
local radio=${obj%%.X_ADB_PowerManagement*} radioName RadioEnable
cmclient -v radioName GETV "$radio.Name"
cmclient -v RadioEnable GETV "Device.WiFi.Radio.[Name=$radioName].Enable"
[ -e "$radioPowerMng.$radioName" ] && rm -f "$radioPowerMng.$radioName"
if [ "$RadioEnable" = "true" ]; then
configure_power_mng "$radioName" "$radioPowerMng"
wifi_config_start "true" "$radioName" "$radio"
fi
}
case $op in
"s")
check_status
;;
esac
exit 0
