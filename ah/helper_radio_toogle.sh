#!/bin/sh
can_enable_main() {
return 0
}
can_enable_ap() {
local apObj="$1" ret=0 pwd="" mode ssid
cmclient -v mode GETV "$apObj.Security.ModeEnabled"
case $mode in
"WPA"*)
cmclient -v pwd GETV "$apObj.Security.KeyPassphrase"
[ ${#pwd} -eq 0 ] && ret=1
;;
"WEP"*)
cmclient -v pwd GETV "$apObj.Security.WEPKey"
[ ${#pwd} -eq 0 ] && ret=1
;;
esac
if [ $ret -eq 0 ]; then
cmclient -v ssid GETV "$apObj.SSIDReference"
cmclient -v ssid GETV "$ssid.SSID"
[ ${#ssid} -eq 0 ] && ret=1
fi
return $ret
}
radio_main_toggle() {
local radioEnable n ssid_obj ap_obj
cmclient -v n GETO "Device.WiFi.Radio.[Enable=true]"
[ ${#n} -gt 0 ] && radioEnable="true"
cmclient -v n GETO Device.WiFi.Radio
for n in $n; do
cmclient -v ssid_obj GETO "Device.WiFi.SSID.[Name=%($n.Name)]"
cmclient -v ap_obj GETO "Device.WiFi.AccessPoint.[SSIDReference=$ssid_obj]"
if [ "$radioEnable" = "true" ]; then
cmclient SET "$n.Enable" false > /dev/null
cmclient SET "$ssid_obj.Enable" false > /dev/null
cmclient SET "$ap_obj.Enable" false > /dev/null
elif can_enable_ap "$ap_obj"; then
cmclient SET "$ssid_obj.Enable" true > /dev/null
cmclient SET "$ap_obj.Enable" true > /dev/null
cmclient -u boot SET "$n.Enable" true > /dev/null
else
echo "The AP $ap_obj isn't configured, nothing to do."
fi
done
}
