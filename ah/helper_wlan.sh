#!/bin/sh
. /etc/ah/helper_svc.sh
. /etc/ah/helper_provisioning.sh
radioPowerMng="/tmp/wlan/PowerMngConf"
radioTempFile="/tmp/wlan/radioConf"
ssidTempFile="/tmp/wlan/ssid"
apTempFile="/tmp/wlan/ap"
hostapdBaseFile="/etc/wlan/config/hostapd_default.conf"
hostapdConf="/tmp/wlan/config/hostapd.conf"
wifi_kill_hostapd() {
local rn="$1"
[ -x "/usr/sbin/bsd" ] && cmclient SET "Device.WiFi.X_ADB_BandSteering.[Enable=true].Status" "Error_RadioOff"
help_svc_stop "hostapd_$rn" "/var/run/hostapd_$rn.pid" "2"
rm -f /var/run/hostapd-$rn/$rn
}
wifi_start_hostapd() {
local rn="$1" i=0
wifi_kill_hostapd $rn
help_svc_start "hostapd -B $hostapdConf.$rn -P /var/run/hostapd_$rn.pid" "hostapd_$rn" 'daemon' '' '' '2' "/var/run/hostapd_$rn.pid"
while [ $((i=i+1)) -le 100 ]; do
[ -e /var/run/hostapd-$rn/$rn ] && break
sleep 0.1
done
if [ -x "/usr/sbin/bsd" ]; then
cmclient SET "Device.WiFi.X_ADB_BandSteering.[Enable=true].Enable" "true"
fi
[ -x "/usr/sbin/acsd" ] && /etc/init.d/acsd.sh restart
}
wifi_set_bss_status() {
local _path="$1" _up="$2"
echo "### $AH_NAME: SET <$_path.Status> <$_up> ###"
cmclient -u "WiFiSSID${_path}" SET "$_path.Status" "$_up" &
}
clean_associated_clients() {
local radioObj="$1" ssid= i=
cmclient -v ssid GETO "Device.WiFi.SSID.[LowerLayers=$radioObj]"
for ssid in $ssid; do
cmclient -v i GETO Device.WiFi.AccessPoint.[SSIDReference=$ssid].AssociatedDevice
for i in $i; do
cmclient DEL $i
done
done
}
wifi_wps_ap_pin() {
local radioName="$1" mainSSID= mainAP= ap_enable=
cmclient -v mainSSID GETO "Device.WiFi.SSID.[Name=$radioName]"
cmclient -v mainAP GETO "Device.WiFi.AccessPoint.[SSIDReference=$mainSSID]"
cmclient -v ap_enable GETV "$mainAP.Enable"
if [ "$ap_enable" = "true" ]; then
local wps_enable= isSetupLocked=
cmclient -v wps_enable GETV "$mainAP.WPS.Enable"
cmclient -v isSetupLocked GETV "$mainAP.WPS.X_ADB_SetupLock"
if [ "$wps_enable" = "true" -a "$isSetupLocked" = "false"  ]; then
local wps_supp= wps_enab=
cmclient -v wps_supp GETV "$mainAP.WPS.ConfigMethodsSupported"
cmclient -v wps_enab GETV "$mainAP.WPS.ConfigMethodsEnabled"
case $wps_supp in
*"PIN"* )
case $wps_enab in
*"PIN"*)
/usr/sbin/hostapd_cli -p /var/run/hostapd-${radioName} wps_ap_pin random &
return
;;
esac
;;
esac
fi
fi
/usr/sbin/hostapd_cli -p /var/run/hostapd-${radioName} wps_ap_pin disable &
}
wifi_force_auto_channel_scan() {
local _ifname="$1"
local radioName="${_ifname%%.*}"
if [ -x /usr/sbin/acs_cli ]; then
acs_cli -i ${radioName} autochannel $_ifname
else
/usr/sbin/hostapd_cli -p /var/run/hostapd-${radioName} autochannel $_ifname
fi
}
wifi_align_status() {
local radio_enable="$1" radio_name="$2" radio_obj="$3" ssid_path ap_path ssid_enable_val
if [ "$radio_enable" = "false" ]; then
cmclient -v ssid_path GETO "Device.WiFi.SSID.[LowerLayers=$radio_obj].[Enable=false].[Status!Down]"
for ssid_path in $ssid_path; do
wifi_set_bss_status "$ssid_path" "Down"
done
cmclient -v ssid_path GETO "Device.WiFi.SSID.[LowerLayers=$radio_obj].[Enable=true].[Status!LowerLayerDown]"
for ssid_path in $ssid_path; do
wifi_set_bss_status "$ssid_path" "LowerLayerDown"
done
cmclient -v ssid_path GETO "Device.WiFi.SSID.[LowerLayers=$radio_obj].[Status!Up]"
for ssid_path in $ssid_path; do
cmclient SETE "Device.WiFi.AccessPoint.*.[SSIDReference=$ssid_path].[Status=Enabled].Status" "Disabled"
done
return
fi
cmclient -v ssid_path GETO "Device.WiFi.SSID.[Name=$radio_name]"
cmclient -v ssid_enable GETV "${ssid_path}.Enable"
cmclient -v ap_path GETO "Device.WiFi.AccessPoint.*.[SSIDReference=$ssid_path].[Enable=true]"
if [ "$ssid_enable" = "false" -o ${#ap_path} -eq 0 ]; then
cmclient -v ssid_path GETO "Device.WiFi.SSID.[LowerLayers=$radio_obj].[Status!Down]"
for ssid_path in $ssid_path; do
wifi_set_bss_status "$ssid_path" "Down"
done
return
else
wifi_set_bss_status "$ssid_path" "Up"
fi
cmclient -v ssid_path GETO "Device.WiFi.SSID.[LowerLayers=$radio_obj].[Name!$radio_name].[Enable=true]"
for ssid_path in $ssid_path; do
cmclient -v ap_path GETO "Device.WiFi.AccessPoint.*.[SSIDReference=$ssid_path].[Enable=true]"
[ ${#ap_path} -eq 0 ] && wifi_set_bss_status "$ssid_path" "Down" || wifi_set_bss_status "$ssid_path" "Up"
done
cmclient -v ssid_path GETO "Device.WiFi.SSID.[LowerLayers=$radio_obj].[Name!$radio_name].[Enable=false].[Status!Down]"
for ssid_path in $ssid_path; do
wifi_set_bss_status "$ssid_path" "Down"
done
cmclient -v ssid_path GETO "Device.WiFi.SSID.[LowerLayers=$radio_obj].[Status=Up]"
for ssid_path in $ssid_path; do
cmclient SETE "Device.WiFi.AccessPoint.*.[SSIDReference=$ssid_path].[Enable=true].[Status!Enabled].Status" "Enabled"
done
}
wifi_prepare_file() {
local radioName="$1" radioObj="$2" ssid_enable iov iov_comment="" OFB
[ -e "$hostapdConf.$radioName" ] && rm -f $hostapdConf.$radioName
echo "interface=$radioName" >> $hostapdConf.$radioName
echo "ctrl_interface=/var/run/hostapd-$radioName" >> $hostapdConf.$radioName
echo "ctrl_interface_group=0" >> $hostapdConf.$radioName
cat $hostapdBaseFile >> $hostapdConf.$radioName
[ ! -e "$radioTempFile.$radioName" ] && return 0
cat $radioTempFile.$radioName >> $hostapdConf.$radioName
cmclient -v iov GETV "$radioObj.X_ADB_InterferenceOverride"
echo "${iov_comment}interference_override=$iov" >> $hostapdConf.$radioName
cmclient -v ssid GETV "Device.WiFi.SSID.[LowerLayers=$radioObj].Name"
for ssid in $ssid; do
cmclient -v ssid_enable GETV Device.WiFi.SSID.[Name=$ssid].Enable
if [ "$ssid_enable" = "true" -a -e "$ssidTempFile.$ssid" -a -e "$apTempFile.$ssid" ]; then
cat $ssidTempFile.$ssid >> $hostapdConf.$radioName
cat $apTempFile.$ssid >> $hostapdConf.$radioName
elif [ "$ssid" = "$radioName" ]; then
return 0
fi
done
[ -e "$radioPowerMng.$radioName" ] && cat $radioPowerMng.$radioName >> $hostapdConf.$radioName
wifiradio_adjust_hostapd_conf $hostapdConf.$radioName
return 1
}
wifi_config_start() {
local radio_enabled="$1" radio_name="$2" radio_obj="$3"
if [ "$user" != "POSTPROVISIONING" ]; then
if [ "$radio_enabled" = "true" ]; then
help_post_provisioning_add "$radio_obj.Enable" "true" "Default" || return 0
else
help_post_provisioning_remove "$radio_obj.Enable" "true"
fi
fi
if [ "$radio_enabled" = "true" ]; then
cmclient -v radioStds GETV "$radio_obj.SupportedStandards"
case $radioStds in
*ac*)
wifiradio_bf_cal "$radio_name"
;;
esac
if ! wifi_prepare_file "$radio_name" "$radio_obj"; then
wifi_start_hostapd "$radio_name"
wifi_align_status "true" "$radio_name" "$radio_obj"
wifi_wps_ap_pin "$radio_name"
logger -t "hostapd" -p 4 "Radio \"$radio_name\" enabled"
fi
else
wifi_align_status "false" "$radio_name" "$radio_obj"
fi
}
wifi_stop() {
local radio_name="$1" radio_obj="$2"
if [ -s /var/run/hostapd_$radio_name.pid ]; then
wifi_kill_hostapd "$radio_name"
fi
clean_associated_clients "$radio_obj"
logger -t "hostapd" -p 4 "Radio \"$radio_name\" disabled"
}
wifi_set_bss_up() {
local _ifname="$1" _status="$2"
local radioName="${_ifname%%.*}" confVal
[ "$_status" = "Up" ] && confVal="up" || confVal="down"
[ -s /var/run/hostapd_$radioName.pid ] && hostapd_cli -p /var/run/hostapd-${radioName} bss "$_ifname" "$confVal"
return 0
}
wifi_scan_ap() {
local radio_dev="$1" param_p="$2" scan_output= counter=0 ac= pid1=0 pid2=1 tmp=
cmclient -v ac GETV "WiFi.Radio.[Enable=true].[Name=$radio_dev].AutoChannelEnable"
if [ "$ac" = "true" ]; then
read -r pid1 < "/var/run/hostapd_${radio_dev}.pid" || pid1="NOPROCESS"
pid2=`pgrep -f hostapd.*${radio_dev}`
if [ $pid1 -eq $pid2 ]; then
if [ -x /usr/sbin/acs_cli ]; then
ac=`acs_cli -i ${radio_dev} csscan`
tmp="finished"
else
ac=`hostapd_cli -p /var/run/hostapd-${radio_dev} acs_csscan`
tmp="SCHEDULED"
fi
fi
fi
if [ "${ac#*$tmp}" = "$ac" ]; then
wifiradio_passive_scan "$radio_dev" "$param_p" || return 1
fi
wifiradio_parse_scanresults "scan_output" "$radio_dev" || return 2
echo -e "$scan_output"
return 0
}
update_pcie_aspm_status()
{
return 0
}
