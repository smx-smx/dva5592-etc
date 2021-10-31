#!/bin/sh
wifi_reconf_wpa() {
local _ssid="$1" wan_addr="" _wa1="" _s="" _s1="" sha256=
if [ "$wifi_sec_mode" = "WPA-Enterprise" -o "$wifi_sec_mode" = "WPA2-Enterprise" -o "$wifi_sec_mode" = "WPA-WPA2-Enterprise" ]; then
if [ -n "$wifi_radius_serv_ip" -a -n "$wifi_radius_serv_port" -a -n "$wifi_radius_secret" ]; then
echo "auth_server_addr=$wifi_radius_serv_ip" >> $apTempFile.$_ssid
echo "auth_server_port=$wifi_radius_serv_port" >> $apTempFile.$_ssid
echo "auth_server_shared_secret=$wifi_radius_secret" >> $apTempFile.$_ssid
echo "rsn_preauth=1" >> $apTempFile.$_ssid
if [ -n "$wifi_second_radius_serv_ip" ]; then
echo "auth_server_addr=$wifi_second_radius_serv_ip" >> $apTempFile.$_ssid
if [ -n "$wifi_second_radius_serv_port" ]; then
echo "auth_server_port=$wifi_second_radius_serv_port" >> $apTempFile.$_ssid
else
echo "auth_server_port=$wifi_radius_serv_port" >> $apTempFile.$_ssid
fi
if [ -n "$wifi_second_radius_secret" ]; then
echo "auth_server_shared_secret=$wifi_second_radius_secret" >> $apTempFile.$_ssid
else
echo "auth_server_shared_secret=$wifi_radius_secret" >> $apTempFile.$_ssid
fi
fi
[ "$wifi_mfp_mode" = Required -a "$wifi_sec_mode" = WPA2-Enterprise ] && wifiradio_get_hw_support "mfp" && sha256="-SHA256"
echo "wpa_key_mgmt=WPA-EAP$sha256" >> $apTempFile.$_ssid
echo "ieee8021x=1" >> $apTempFile.$_ssid
IFS=' ' read -r _ _ _ _s wan_addr _s1 _wa1<<-EOF
`ip route get $wifi_radius_serv_ip`
EOF
[ "$_s1" = "src" ] && wan_addr="$_wa1" && _s="$_s1"
[ ${#wan_addr} -gt 0 -a "$_s" = "src" ] && echo "own_ip_addr=$wan_addr" >> $apTempFile.$_ssid
echo "nas_identifier=ADBITALIA" >> $apTempFile.$_ssid
fi
if [ "$wifi_acct_enable" = "true" -a -n "$wifi_acct_serv_ip" -a -n "$wifi_acct_serv_port" ]; then
echo "acct_server_addr=$wifi_acct_serv_ip" >> $apTempFile.$_ssid
echo "acct_server_port=$wifi_acct_serv_port" >> $apTempFile.$_ssid
[ "$wifi_acct_serv_strict_rfc" = "true" ] && echo "acct_server_strict_rfc2866_stats=1" >> $apTempFile.$_ssid || \
echo "acct_server_strict_rfc2866_stats=0" >> $apTempFile.$_ssid
echo "radius_acct_interim_interval=$wifi_acct_interim" >> $apTempFile.$_ssid
[ ${#wifi_acct_secret} -gt 0 ] && echo "acct_server_shared_secret=$wifi_acct_secret" >> $apTempFile.$_ssid
fi
else
if [ -n "$wifi_psk" ]; then
echo "wpa_psk=$wifi_psk" >> $apTempFile.$_ssid
elif [ -n "$wifi_pass_key" ]; then
echo "wpa_passphrase=$wifi_pass_key" >> $apTempFile.$_ssid
fi
[ "$wifi_mfp_mode" = Required -a "$wifi_sec_mode" = "WPA2-Personal" ] && wifiradio_get_hw_support "mfp" && sha256="-SHA256"
echo "wpa_key_mgmt=WPA-PSK$sha256" >> $apTempFile.$_ssid
fi
[ -n "$wifi_rekey" ] && echo "wpa_group_rekey=$wifi_rekey" >> $apTempFile.$_ssid
case "$wifi_sec_mode" in
WPA-WPA2-*)
wifi_enc_type="TKIP-AES"
echo "wpa_pairwise=TKIP CCMP" >> $apTempFile.$_ssid
;;
WPA2-*)
wifi_enc_type="AES"
echo "wpa_pairwise=CCMP" >> $apTempFile.$_ssid
;;
*)
local ssidObj radioObj hw_mode
cmclient -v ssidObj GETV "$ap_obj.SSIDReference"
cmclient -v radioObj GETV "$ssidObj.LowerLayers"
cmclient -v hw_mode GETV "$radioObj.OperatingStandards"
case "$hw_mode" in
*"n"*)
wifi_enc_type="TKIP-AES"
echo "wpa_pairwise=TKIP CCMP" >> $apTempFile.$_ssid
;;
*)
wifi_enc_type="TKIP"
echo "wpa_pairwise=TKIP" >> $apTempFile.$_ssid
;;
esac
;;
esac
cmclient -u ${ap_obj}.Security SET "$ap_obj.Security.X_ADB_EncryptionMode" "$wifi_enc_type"
}
wifi_reconf_mfp()
{
wifiradio_get_hw_support "mfp" || return 0
case $wifi_sec_mode in
WPA2-Personal | WPA2-Enterprise)
case $wifi_mfp_mode in
Required)	echo 'ieee80211w=2' ;;
Disabled)	echo 'ieee80211w=0' ;;
*)		echo 'ieee80211w=1' ;;
esac
echo "assoc_sa_query_max_timeout=60"
echo "assoc_sa_query_retry_timeout=45"
;;
*)
echo "ieee80211w=0"
;;
esac >> $apTempFile.$ssid
}
wifi_reconf_wep() {
local _ssid="$1" _wep="$2"
if [ -n "$wifi_wep_key" ]; then
echo "wep_default_key=0" >> $apTempFile.$_ssid
echo "wep_key0=$wifi_wep_key" >> $apTempFile.$_ssid
fi
[ "$_wep" = "WEP-64" ] &&\
echo "wep_pairwise=WEP40" >> $apTempFile.$_ssid ||\
echo "wep_pairwise=WEP104" >> $apTempFile.$_ssid
}
wifi_misconfigured() {
local ap_obj=$1
cmclient SETE ${ap_obj}.Status Error_Misconfigured
exit 0
}
wifi_validate() {
local ap_obj=$1 ssid key=$3
cmclient -v ssid GETV WiFi.SSID.[Name=$2].SSID
if [ -z "$ssid" -o -z "$key" ]; then
wifi_misconfigured $ap_obj
return 1
else
cmclient -u NoWiFi SET ${ap_obj}.Status Enabled
fi
return 0
}
wifi_validate_enterprise() {
local ap_obj=$1 ssid
cmclient -v ssid GETV WiFi.SSID.[Name=$2].SSID
if [ -z "$ssid" ]; then
wifi_misconfigured $ap_obj
return 1
fi
if [ -n "$wifi_radius_serv_ip" ]; then
if [ $wifi_radius_serv_port -eq 0 -o -z "$wifi_radius_secret" ]; then
wifi_misconfigured $ap_obj
return 1
fi
else
wifi_misconfigured $ap_obj
return 1
fi
if [ -n "$wifi_second_radius_serv_ip" ]; then
if [ $wifi_second_radius_serv_port -eq 0 -o -z "$wifi_second_radius_secret" ]; then
wifi_misconfigured $ap_obj
return 1
fi
fi
return 0
}
wifi_reconf_all_security() {
local ap_obj="$1" ssid="$2"
case $wifi_sec_mode in
"WEP-64" | "WEP-128" )
wifi_validate "$ap_obj" "$ssid" "$wifi_wep_key"
wifi_reconf_wep "$ssid" "$wifi_sec_mode"
;;
"WPA-Personal" )
echo "wpa=1" >> $apTempFile.$ssid
wifi_validate "$ap_obj" "$ssid" "$wifi_pass_key"
wifi_reconf_wpa "$ssid"
;;
"WPA2-Personal" )
echo "wpa=2" >> $apTempFile.$ssid
wifi_validate "$ap_obj" "$ssid" "$wifi_pass_key"
wifi_reconf_wpa "$ssid"
;;
"WPA-WPA2-Personal" )
echo "wpa=3" >> $apTempFile.$ssid
wifi_validate "$ap_obj" "$ssid" "$wifi_pass_key"
wifi_reconf_wpa "$ssid"
;;
"WPA-Enterprise" )
echo "wpa=1" >> $apTempFile.$ssid
wifi_validate_enterprise "$ap_obj" "$ssid"
wifi_reconf_wpa "$ssid"
;;
"WPA2-Enterprise" )
echo "wpa=2" >> $apTempFile.$ssid
wifi_validate_enterprise "$ap_obj" "$ssid"
wifi_reconf_wpa "$ssid"
;;
"WPA-WPA2-Enterprise" )
echo "wpa=3" >> $apTempFile.$ssid
wifi_validate_enterprise "$ap_obj" "$ssid"
wifi_reconf_wpa "$ssid"
;;
"None" | *)
;;
esac
wifi_reconf_mfp
}
service_read_ap_acct() {
local ap_obj="$1"
if [ ${#ap_obj} -gt 0 ]; then
cmclient -v wifi_acct_enable GETV "$ap_obj.Accounting.Enable"
cmclient -v wifi_acct_serv_ip GETV "$ap_obj.Accounting.ServerIPAddr"
cmclient -v wifi_acct_serv_strict_rfc GETV "$ap_obj.Accounting.X_ADB_StrictRfc2866Stats"
cmclient -v wifi_acct_serv_port GETV "$ap_obj.Accounting.ServerPort"
cmclient -v wifi_acct_secret GETV "$ap_obj.Accounting.Secret"
cmclient -v wifi_acct_interim GETV "$ap_obj.Accounting.InterimInterval"
else
wifi_acct_enable="$newEnable"
wifi_acct_serv_ip="$newServerIPAddr"
wifi_acct_serv_strict_rfc="$newX_ADB_StrictRfc2866Stats"
wifi_acct_serv_port="$newServerPort"
wifi_acct_secret="$newSecret"
wifi_acct_interim="$newInterimInterval"
fi
}
service_read_ap_security() {
local ap_obj="$1"
if [ -n "$ap_obj" ]; then
cmclient -v wifi_sec_mode GETV "$ap_obj.Security.ModeEnabled"
cmclient -v wifi_enc_type GETV "$ap_obj.Security.X_ADB_EncryptionMode"
cmclient -v wifi_wep_key GETV "$ap_obj.Security.WEPKey"
cmclient -v wifi_psk GETV "$ap_obj.Security.PreSharedKey"
cmclient -v wifi_pass_key GETV "$ap_obj.Security.KeyPassphrase"
cmclient -v wifi_rekey GETV "$ap_obj.Security.RekeyingInterval"
cmclient -v wifi_radius_serv_ip GETV "$ap_obj.Security.RadiusServerIPAddr"
cmclient -v wifi_radius_serv_port GETV "$ap_obj.Security.RadiusServerPort"
cmclient -v wifi_radius_secret GETV "$ap_obj.Security.RadiusSecret"
cmclient -v wifi_second_radius_serv_ip GETV "$ap_obj.Security.SecondaryRadiusServerIPAddr"
cmclient -v wifi_second_radius_serv_port GETV "$ap_obj.Security.SecondaryRadiusServerPort"
cmclient -v wifi_second_radius_secret GETV "$ap_obj.Security.SecondaryRadiusSecret"
cmclient -v wifi_mfp_mode GETV "$ap_obj.Security.X_ADB_MFPModeEnabled"
else
wifi_sec_mode="$newModeEnabled"
wifi_enc_type="$newX_ADB_EncryptionMode"
wifi_wep_key="$newWEPKey"
wifi_psk="$newPreSharedKey"
wifi_pass_key="$newKeyPassphrase"
wifi_rekey="$newRekeyingInterval"
{ [ ${setKeyPassphrase:-0} -eq 1 ] && cmclient SETE "$ap_object.Security.PreSharedKey" ""; } \
|| { [ ${setPreSharedKey:-0} -eq 1 ] && cmclient SETE "$ap_object.Security.KeyPassphrase" ""; }
wifi_radius_serv_ip="$newRadiusServerIPAddr"
wifi_radius_serv_port="$newRadiusServerPort"
wifi_radius_secret="$newRadiusSecret"
wifi_second_radius_serv_ip="$newSecondaryRadiusServerIPAddr"
wifi_second_radius_serv_port="$newSecondaryRadiusServerPort"
wifi_second_radius_secret="$newSecondaryRadiusSecret"
wifi_mfp_mode=$newX_ADB_MFPModeEnabled
fi
}
service_config_ap_security() {
local sec_obj="$1" ap_obj="$2" ssid_ifname="$3" acc_obj="$4"
[ -n "$sec_obj" ] &&\
service_read_ap_security ||\
service_read_ap_security "$ap_obj"
[ ${#acc_obj} -gt 0 ] &&\
service_read_ap_acct ||\
service_read_ap_acct "$ap_obj"
[ -n "$ssid_ifname" ] && wifi_reconf_all_security "$ap_obj" "$ssid_ifname"
}
