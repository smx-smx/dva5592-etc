#!/bin/sh
AH_NAME="WLANConfiguration"
[ "$user" != "CWMP" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
. /etc/ah/helper_wlan.sh
. /etc/ah/target.sh
trLookupParam=""
trLookupVal=""
service_lookup_encryption_mode() {
local _tr098enc="$1"
[ "$2" != "_tr181val" ] local _tr181val
case "$_tr098enc" in
"TKIPEncryption") 	_tr181val="TKIP" ;;
"AESEncryption") 	_tr181val="AES" ;;
"TKIPandAESEncryption")	_tr181val="TKIP-AES" ;;
esac
eval $2='$_tr181val'
}
service_lookup_param() {
local _tr098obj="$1" _tr098="$2" _tr098val="$3" _apObj="$4" _ssidObj="$5" _tr181="" _tr181val="" mode
_tr181val="$_tr098val"
case "$_tr098" in
"Total"*)
_tr181="$_ssidObj.Stats.${_tr098#*Total}"
;;
"Channel" | "AutoChannelEnable" | "PossibleChannels" | "ChannelsInUse" | \
"RegulatoryDomain" | "TransmitPower" | "TransmitPowerSupported" | \
"X_ADB_WMMGlobalEnable" | "X_ADB_WMMGlobalNoAck" | \
"X_ADB_STBC_Rx" | "X_ADB_STBC_Tx" | "X_ADB_AMPDU" | \
*"Received" | *"Sent")
_tr181="$_tr098"
;;
"MaxBitRate")
_tr181="$_tr098"
if [ "$_tr098val" = "Auto" ]; then
_tr181val="0"
fi
;;
"RadioEnabled")
_tr181="Enable"
;;
"BasicDataTransmitRates" | "OperationalDataTransmitRates")
_tr181="X_ADB_$_tr098"
;;
"Enable" | "Status" | "SSID" | "BSSID")
_tr181="$_ssidObj.$_tr098"
;;
"MACAddressControlEnabled")
_tr181="$_ssidObj.X_ADB_MacMode"
[ "$_tr098val" = "true" ] && _tr181val="Accept" || _tr181val="None"
;;
"Standard")
cmclient -v _tr181 GETV $_tr098obj.X_ADB_TR181Name
_tr181="$_tr181".OperatingStandards
if [ "$_tr098val" = "g-only" ]; then
_tr181val="g"
elif [ "$_tr098val" = "n" ]; then
_tr181val="b,g,n"
fi
;;
"BeaconType")
_tr181="$_apObj.Security.ModeEnabled"
case "$_tr098val" in
"Basic")
_tr181val="WEP-128"
;;
"WPA")
_tr181val="WPA-Personal"
;;
"11i")
_tr181val="WPA2-Personal"
;;
"WPAand11i")
_tr181val="WPA-WPA2-Personal"
;;
esac
;;
"BeaconAdvertisementEnabled")
_tr181="$_apObj.Enable"
;;
"LocationDescription")
_tr181="$_apObj.X_ADB_$_tr098"
;;
"UAPSDEnable" | "WMMEnable" | "SSIDAdvertisementEnabled")
_tr181="$_apObj.$_tr098"
;;
"BasicEncryptionModes" | "BasicAuthenticationMode" | "WEPEncryptionLevel")
_tr181="$_apObj.Security.ModeEnabled"
cmclient -v mode GETV "$_tr181"
if [ "$mode" = "WEP-64" -o "$mode" = "WEP-128" -o "$mode" = "None" ]; then
if [ "$_tr098" = "WEPEncryptionLevel" -a "$_tr098val" = "40-bit" ]; then
_tr181val="WEP-64"
elif [ "$_tr098val" = "None" ]; then
_tr181val="None"
else
_tr181val="WEP-128"
fi
fi
;;
"WPAEncryptionModes" | "IEEE11iEncryptionModes")
_tr181="$_apObj.Security.X_ADB_EncryptionMode"
service_lookup_encryption_mode "$_tr098val" _tr181val
;;
"KeyPassphrase")
_tr181="$_apObj.Security.$_tr098"
;;
"WEPKey")
_tr181="$_apObj.Security.$_tr098"
;;
"ConfigMethodsEnabled" | "ConfigMethodsSupported" )
_tr181="$_apObj.WPS.$_tr098"
_tr181val=$(help_str_replace_all "Display" "PIN" $_tr098val)
;;
esac
trLookupParam="$_tr181"
trLookupVal="$_tr181val"
}
service_set_param() {
local radioObj="$1"
local temp_param="$2"
local _val="$3"
local apObj="$4"
local ssidObj="$5"
local param=""
local obj_name=""
service_lookup_param "$radioObj" "$temp_param" "$_val" "$apObj" "$ssidObj"
param="$trLookupParam"
if [ -n "$trLookupVal" ]; then
_val="$trLookupVal"
else
return
fi
case $param in
*.* )
if [ -z "$setm_params" ]; then
setm_params="$param=$_val"
elif [ "$setm_params" = "${setm_params%$param=$_val*}" ]; then
setm_params="$setm_params	$param=$_val"
fi
;;
"")
return
;;
*)
if [ -z "$setm_params" ]; then
setm_params="$radio_obj.$param=$_val"
elif [ "$setm_params" = "${setm_params%$radio_obj.$param=$_val*}" ]; then
setm_params="$setm_params	$radio_obj.$param=$_val"
fi
;;
esac
}
service_lookup_value() {
local _tr181param="$1" _tr181val="$2" _obj98="$3" _tr098val="" _tr181val2=""
_tr098val="$_tr181val"
case "$_tr181param" in
"X_ADB_MacMode")
[ "$_tr181val" = "Accept" ] && _tr098val="true" || _tr098val="false"
;;
"Status")
help98_get_ifstatus _tr098val "$_tr181val"
cmclient -v _tr181val2 GETV "Device.WiFi.AccessPoint.[$PARAM_TR098=$_obj98].Status"
[ "$_tr098val" = "Up" -a "$_tr181val2" = "Enabled" ] || _tr098val="Disabled"
;;
"Enable")
_tr098val="$_tr181val"
cmclient -v _tr181val2 GETV "Device.WiFi.AccessPoint.[$PARAM_TR098=$_obj98].Enable"
[ "$_tr098val" = "true" -a "$_tr181val2" = "true" ] || _tr098val="false"
;;
"OperatingStandards")
case $_tr181val in
"g")
_tr098val="g-only" ;;
"g,n"|"n,g"|"b,g,n"|"b,n,g"|"g,b,n"|"g,n,b"|\
"n,b,g"|"n,g,b")
_tr098val="n"	;;
"b,g"|"g,b")
_tr098val="g"	;;
"a"|"b")
_tr098val="$_tr181val"	;;
esac
;;
"X_ADB_EncryptionMode" )
case $_tr181val in
"TKIP")
_tr098val="TKIPEncryption"
;;
"AES")
_tr098val="AESEncryption"
;;
"TKIP-AES")
_tr098val="TKIPandAESEncryption"
;;
esac
;;
"ConfigMethodsEnabled" | "ConfigMethodsSupported" )
_tr098val=$(help_str_replace_all "PIN" "Display" $_tr181val)
;;
"ModeEnabled" )
case $_tr181val in
"None")
if [ "$param98" = "WEPEncryptionLevel" ]; then
_tr098val="Disabled"
elif [ "$param98" = "BeaconType" ]; then
_tr098val="Basic"
else
_tr098val="None"
fi
;;
"WEP-64" | "WEP-128")
if [ "$param98" = "BeaconType" ]; then
_tr098val="Basic"
elif [ "$param98" = "BasicEncryptionModes" ]; then
_tr098val="WEPEncryption"
elif [ "$param98" = "BasicAuthenticationMode" ]; then
_tr098val="SharedAuthentication"
elif [ "$param98" = "WEPEncryptionLevel" ]; then
[ "$_tr181val" = "WEP-64" ] && _tr098val="40-bit" || _tr098val="104-bit"
fi
;;
"WPA-Personal" )
if [ "$param98" = "BeaconType" ]; then
_tr098val="WPA"
elif [ "$param98" = "BasicEncryptionModes" ]; then
_tr098val="WEPEncryption"
elif [ "$param98" = "BasicAuthenticationMode" ]; then
_tr098val="SharedAuthentication"
elif [ "$param98" = "WEPEncryptionLevel" ]; then
_tr098val="Disabled"
fi
;;
"WPA2-Personal" )
if [ "$param98" = "BeaconType" ]; then
_tr098val="11i"
elif [ "$param98" = "BasicEncryptionModes" ]; then
_tr098val="WEPEncryption"
elif [ "$param98" = "BasicAuthenticationMode" ]; then
_tr098val="SharedAuthentication"
elif [ "$param98" = "WEPEncryptionLevel" ]; then
_tr098val="Disabled"
fi
;;
"WPA-WPA2-Personal" )
if [ "$param98" = "BeaconType" ]; then
_tr098val="WPAand11i"
elif [ "$param98" = "BasicEncryptionModes" ]; then
_tr098val="WEPEncryption"
elif [ "$param98" = "BasicAuthenticationMode" ]; then
_tr098val="SharedAuthentication"
elif [ "$param98" = "WEPEncryptionLevel" ]; then
_tr098val="Disabled"
fi
;;
esac
;;
*)
;;
esac
echo "$_tr098val"
}
service_get() {
local temp_obj="$1" param98="$2" apObj="$3" ssidObj="$4" param181=""
cmclient -v radio_obj GETV "$temp_obj.X_ADB_TR181Name"
service_lookup_param "$temp_obj" "$param98" "" "$apObj" "$ssidObj"
param181="$trLookupParam"
case $param181 in
*.* )
cmclient -v paramval GETV "$param181"
param181="${param181##*.}"
;;
"")
paramval=""
;;
"Channel" )
cmclient -v is_autoch GETV "$obj.AutoChannelEnable"
if [ "$is_autoch" = "true" ]; then
wifiradio_get_current_channel "$wifi_ifname"
return
else
cmclient -v paramval GETV "$radio_obj.Channel"
fi
;;
"PossibleChannels" )
wifiradio_get_channel_list "$wifi_ifname"
return
;;
"ChannelsInUse" )
cmclient -v paramval GETV "$radio_obj.ChannelsInUse"
;;
*"Received"|*"Sent")
help_get_base_stats "$obj.$param98" "$wifi_ifname"
return
;;
"TransmitPower")
cmclient -v paramval GETV "$radio_obj.TransmitPower"
[ $paramval -eq -1 ] && paramval=100
;;
"TransmitPowerSupported")
cmclient -v paramval GETV "$radio_obj.TransmitPowerSupported"
paramval=${paramval#-1,}
;;
*)
cmclient -v paramval GETV "$radio_obj.$param181"
;;
esac
case "$param98" in
"Channel"|"ChannelsInUse"|"PossibleChannels"|*"Received"|*"Sent")
echo "$paramval"
;;
*)
service_lookup_value "$param181" "$paramval" "$temp_obj"
;;
esac
}
configure_security()
{
local tr181_security=$1.Security security_mode wpa_cipher wepkey_length beacon_type=$newBeaconType \
basic_encryption_mode=$newBasicEncryptionModes supportedModes match="" encryptionModes=""
[ -z "$beacon_type" ] && cmclient -v beacon_type -u $user GETV $obj.BeaconType
if [ "$changedWEPKey" = 1 ]; then
setm_params="${setm_params}${setm_params:+	}$tr181_security.WEPKey=$newWEPKey"
setm_params="${setm_params}${setm_params:+	}$tr181_security.X_ADB_WEPKeyMode=HEX"
fi
if [ "$changedKeyPassphrase" = 1 ]; then
setm_params="${setm_params}${setm_params:+	}$tr181_security.KeyPassphrase=$newKeyPassphrase"
fi
if [ "$changedPreSharedKey" = 1 ]; then
setm_params="${setm_params}${setm_params:+	}$tr181_security.PreSharedKey=$newPreSharedKey"
fi
case "$beacon_type" in
Basic)
[ -z "$basic_encryption_mode" ] && cmclient -v basic_encryption_mode GETV $obj.BasicEncryptionModes
case "$basic_encryption_mode" in
None) security_mode="None" ;;
WEPEncryption)
wepkey_length=${#newWEPKey}
[ $wepkey_length -le 10 ] && security_mode="WEP-64" || security_mode="WEP-128"
;;
esac
;;
11i)
case "$newIEEE11iAuthenticationMode" in
EAPAuthentication) security_mode="WPA2-Enterprise" ;;
PSKAuthentication) security_mode="WPA2-Personal";;
esac
encryptionModes="$newIEEE11iEncryptionModes"
;;
WPA)
case "$newWPAAuthenticationMode" in
EAPAuthentication) security_mode="WPA-Enterprise" ;;
PSKAuthentication) security_mode="WPA-Personal" ;;
esac
encryptionModes="$newWPAEncryptionModes"
;;
WPAand11i)
case "$newWPAAuthenticationMode" in
EAPAuthentication) security_mode="WPA-WPA2-Enterprise" ;;
PSKAuthentication) security_mode="WPA-WPA2-Personal" ;;
esac
encryptionModes="$newWPAEncryptionModes"
;;
esac
case "$encryptionModes" in
TKIPEncryption) wpa_cipher="TKIP";;
AESEncryption) wpa_cipher="AES";;
TKIPandAESEncryption) wpa_cipher="TKIP-AES";;
esac
if [ ${#wpa_cipher} -ge 0 ]; then
cmclient -v supportedModes GETV $tr181_security.X_ADB_EncryptionModesSupported
oldIFS=$IFS
IFS=","
set -- ${supportedModes}
IFS=$oldIFS
for mode; do
expr match $mode ".*$wpa_cipher" && [ ${#match} -eq 0 -o ${#mode} -le ${#match} ] && match=$mode
done
[ ${#match} -gt 0 ] && wpa_cipher=$match
fi
[ ${#wpa_cipher} -gt 0 ] && setm_params="${setm_params}${setm_params:+	}$tr181_security.X_ADB_EncryptionMode=$wpa_cipher"
[ ${#security_mode} -gt 0 ] && setm_params="${setm_params}${setm_params:+	}$tr181_security.ModeEnabled=$security_mode"
}
service_config() {
local val_ret='' setm_ret='' err_val='' setm_params=''
cmclient -v radio_obj GETV "$obj.X_ADB_TR181Name"
cmclient -v ap_obj GETV "$obj.X_ADB_TR181_AP"
cmclient -v ssid_obj GETV "$obj.X_ADB_TR181_SSID"
help_is_changed BeaconType WEPKey IEEE11iAuthenticationMode WPAAuthenticationMode \
BasicEncryptionModes WPAEncryptionModes IEEE11iEncryptionModes \
KeyPassphrase PreSharedKey && configure_security $ap_obj
for i in Enable MACAddressControlEnabled SSID ConfigMethodsSupported ConfigMethodsEnabled \
AutoChannelEnable BasicDataTransmitRates BeaconAdvertisementEnabled BSSID Channel \
LocationDescription MaxBitRate OperationalDataTransmitRates RadioEnabled \
RegulatoryDomain SSIDAdvertisementEnabled UAPSDEnable WMMEnable \
X_ADB_WMMGlobalEnable X_ADB_STBC_Rx X_ADB_STBC_Tx X_ADB_AMPDU ; do
if eval [ \${set${i}:=0} -eq 1 ]; then
eval service_set_param "$obj" "$i" \"\$new${i}\" "$ap_obj" "$ssid_obj"
fi
done
if [ -n "$setm_params" ]; then
cmclient -v setm_ret -u "$AH_NAME" SETM "$setm_params"
err_val=${setm_ret#*ERROR #}
[ "$setm_ret" != "$err_val" ] && err_val=${err_val%% *} && [ ${err_val} -le 10 ] && val_ret=$err_val
fi
[ ${#val_ret} -ne 0 ] && exit ${val_ret}
}
service_add() {
for i in Device.WiFi.SSID Device.WiFi.AccessPoint; do
obj_found=0
cmclient -v tr181obj GETO "$i.[$PARAM_TR098=]"
for tr181obj in $tr181obj; do
cmclient SET "$tr181obj.$PARAM_TR098" "$obj" > /dev/null
obj_found=1
break;
done
if [ "$obj_found" -ne 1 ]; then
tr181obj=`help98_add_tr181obj "$obj" "$i"`
fi
if [ "$i" = "Device.WiFi.SSID" ]; then
cmclient -u "$AH_NAME" SET "$obj.X_ADB_TR181_SSID" "$tr181obj" > /dev/null
else
cmclient -u "$AH_NAME" SET "$obj.X_ADB_TR181_AP" "$tr181obj" > /dev/null
fi
done
help98_add_bridge_availablelist "$obj" "LANInterface"
}
service_delete() {
cmclient -v ssid_obj GETO "Device.WiFi.SSID.*.[$PARAM_TR098=$obj]"
if [ -n "$ssid_obj" ]; then
cmclient SET "$ssid_obj.$PARAM_TR098" "" > /dev/null
fi
cmclient -v ap_obj GETO "Device.WiFi.AccessPoint.*.[$PARAM_TR098=$obj]"
if [ -n "$ap_obj" ]; then
cmclient SET "$ap_obj.$PARAM_TR098" "" > /dev/null
fi
help98_del_bridge_availablelist "$obj"
}
case "$op" in
d)
service_delete
;;
a)
service_add
;;
g)
case "$obj" in
*"Stats"*)
obj="${obj%.*}"
;;
*".WEPKey."*)
obj="${obj%.WEPKey*}"
;;
*".WPS"*)
obj="${obj%.WPS*}"
;;
esac
cmclient -v wifi_ifname GETV "$obj.Name"
cmclient -v ap_obj GETO "Device.WiFi.AccessPoint.[$PARAM_TR098=$obj]"
cmclient -v ssid_obj GETO "Device.WiFi.SSID.[$PARAM_TR098=$obj]"
for arg # Arg list as separate words
do
service_get "$obj" "$arg" "$ap_obj" "$ssid_obj"
done
;;
s)
case "$obj" in
*".PreSharedKey."*)
obj="${obj%.PreSharedKey*}"
;;
*".WEPKey."*)
obj="${obj%.WEPKey*}"
;;
*".WPS"*)
obj="${obj%.WPS*}"
;;
esac
service_config
;;
esac
exit 0
