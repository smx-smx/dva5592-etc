#!/bin/sh
wps_ap_pin="false"
WPS_NOTCONFIGURED=1
WPS_CONFIGURED=2
wifi_reconf_wps_methods() {
	local ssid="$1"
	local methods="$2"
	local confVal=""
	local pbc_in_m1=""
	set -f
	IFS=","
	set -- $methods
	unset IFS
	set +f
	for arg; do
		case $arg in
		"PushButton")
			pbc_in_m1="1"
			method="push_button"
			;;
		"NFCInterface") method="nfc_interface" ;;
		"IntegratedNFCToken") method="int_nfc_token" ;;
		"ExternalNFCToken") method="ext_nfc_token" ;;
		"Ethernet") method="ethernet" ;;
		"USBFlashDrive") method="usba" ;;
		"PIN")
			method="display keypad"
			wps_ap_pin="true"
			;;
		*) continue ;;
		esac
		confVal="$method $confVal"
	done
	echo "config_methods=$confVal" >>$apTempFile.$ssid
	if [ "$wps_ap_pin" = "true" ]; then
		echo "wps_cred_processing=1" >>$apTempFile.$ssid
	fi
	if [ -n "$pbc_in_m1" ]; then
		echo "pbc_in_m1=1" >>$apTempFile.$ssid
	fi
	local _rn _of _uuid=
	cmclient -v _rn GETV "Device.WiFi.RadioNumberOfEntries"
	[ $_rn -le 1 ] && return 0
	cmclient -v _of GETV "Device.WiFi.Radio.OperatingFrequencyBand"
	case "$_of" in
	2.4GHz*5GHz | 5GHz*2.4GHz)
		generateUUID _uuid
		[ -n "$_uuid" ] && printf "uuid=$_uuid\nwps_rf_bands=ag\n" >>$apTempFile.$ssid
		;;
	esac
}
generateUUID() {
	local res=''
	local tempMAC=''
	local nsid=''
	local uuid=''
	local BridgeObj=''
	local LinkObj=''
	local MACAddr=''
	local ssidObj=''
	local myport=''
	local nsid=''
	local bridge=''
	local cmd=''
	cmclient -v ssidObj GETV "$ap_obj.SSIDReference"
	cmclient -v myport GETO "Device.Bridging.Bridge.*.Port.[LowerLayers=$ssidObj].[X_ADB_FakePort!true]"
	bridge=${myport%.Port.*}
	cmclient -v BridgeObj GETO "$bridge.Port.[ManagementPort=true]"
	cmclient -v LinkObj GETO "Device.Ethernet.Link.[LowerLayers=$BridgeObj]"
	cmclient -v MACAddr GETV "$LinkObj.MACAddress"
	if [ -n "$MACAddr" ]; then
		if [ -x /usr/bin/sha1sum ]; then
			cmd="/usr/bin/sha1sum"
		else
			cmd="/usr/bin/md5sum"
		fi
		nsid="526480f8c99b4be5a65558ed5f5d6084"
		res=$(echo -n $nsid$MACAddr | $cmd -)
		res=${res%% -}
		temp1_8=$(expr substr $res 1 8)
		temp2_4=$(expr substr $res 9 4)
		temp3_4=$(expr substr $res 13 4)
		temp4_4=$(expr substr $res 17 4)
		temp5_12=$(expr substr $res 21 12)
		eval "$1=$temp1_8-$temp2_4-$temp3_4-$temp4_4-$temp5_12"
	else
		eval "$1=''"
	fi
}
wifi_add_wps_ie() {
	local ssid="$1"
	cmclient -v device_name GETV "Device.DeviceInfo.ModelName"
	cmclient -v manuf_name GETV "Device.DeviceInfo.Manufacturer"
	cmclient -v serial_num GETV "Device.DeviceInfo.SerialNumber"
	cmclient -v manuf_oui GETV "Device.DeviceInfo.ManufacturerOUI"
	echo "device_name=$device_name" >>$apTempFile.$ssid
	echo "model_name=$device_name" >>$apTempFile.$ssid
	echo "manufacturer=$manuf_name" >>$apTempFile.$ssid
	echo "model_number=$serial_num" >>$apTempFile.$ssid
	echo "serial_number=$serial_num" >>$apTempFile.$ssid
	echo "device_type=6-"$manuf_oui"04-1" >>$apTempFile.$ssid
}
service_read_ap_wps() {
	local ap_obj="$1"
	if [ -n "$ap_obj" ]; then
		cmclient -v wifi_wps_enable GETV "$ap_obj.WPS.Enable"
		cmclient -v wifi_wps_state GETV "$ap_obj.WPS.X_ADB_ConfigurationState"
		cmclient -v wifi_wps_methods GETV "$ap_obj.WPS.ConfigMethodsEnabled"
		cmclient -v wifi_wps_setuplock GETV "$ap_obj.WPS.X_ADB_SetupLock"
	else
		wifi_wps_enable="$newEnable"
		wifi_wps_state="$newX_ADB_ConfigurationState"
		wifi_wps_methods="$newConfigMethodsEnabled"
		wifi_wps_setuplock="$newX_ADB_SetupLock"
	fi
}
service_config_ap_wps() {
	local wps_obj="$1"
	local ap_obj="$2"
	local ssid_ifname="$3"
	local wps_support="false"
	local _mod_en=""
	local _ssid_v=""
	if [ -n "$wps_obj" ]; then
		service_read_ap_wps
	else
		service_read_ap_wps "$ap_obj"
	fi
	cmclient -v _mod_en GETV "$ap_obj.Security.ModeEnabled"
	cmclient -v _ssid_v GETV "$ap_obj.SSIDAdvertisementEnabled"
	case "${_mod_en}-${_ssid_v}" in
	"None-true" | "WPA2-Personal-true" | "WPA-WPA2-Personal-true")
		wps_support="true"
		;;
	*)
		:
		;;
	esac
	if [ -n "$ssid_ifname" ]; then
		if [ "$wifi_wps_enable" = "true" -a "$wps_support" = "true" ]; then
			if [ "$wifi_wps_state" = "NotConfigured" ]; then
				echo "wps_state=$WPS_NOTCONFIGURED" >>$apTempFile.$ssid_ifname
			elif [ "$wifi_wps_state" = "Configured" ]; then
				echo "wps_state=$WPS_CONFIGURED" >>$apTempFile.$ssid_ifname
			fi
			{ [ "$wifi_wps_setuplock" = "true" ] && echo "ap_setup_locked=1" || echo "ap_setup_locked=0"; } >>$apTempFile.$ssid_ifname
			echo "eap_server=1" >>$apTempFile.$ssid_ifname
			wifi_add_wps_ie "$ssid_ifname"
			wifi_reconf_wps_methods "$ssid_ifname" "$wifi_wps_methods"
		fi
	fi
}
