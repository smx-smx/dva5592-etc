#!/bin/sh
service_get() {
	if [ "$1" = ".init" ]; then
		for o in $(cmclient GETO Device.WiFi.Radio.[Enable=true]); do
			obj="$o" init=1 $0
		done
		return 0
	elif [ "${1##*.}" = "Channel" ]; then
		if [ "$(cmclient GETV "${1%.*}".AutoChannelEnable)" = "true" ]; then
			ifn=$(cmclient GETV "${1%.*}".Name)
			dev="${ifn%.*}"
			phy="${dev##*[a-z]}"
			cat /sys/kernel/debug/ieee80211/phy"$phy"/ath9k/wiphy | head -n1 | cut -d'=' -f2 | cut -d' ' -f1
		else
			cmclient GETV "${1%.*}".X_ADB_SetChannel
		fi
		return 0
	elif [ "${1##*.}" = "PossibleChannels" ]; then
		ifn=$(cmclient GETV "${1%.*}".Name)
		dev="${ifn%.*}"
		phy="${dev##*[a-z]}"
		iw phy phy"$phy" info |
			awk '{ if (/MHz/ && !/disabled/ && !/passive/ && !/IBSS/) printf "%s,",$4  }' |
			sed -e "s/[][]//g" -e 's/,$/\n/'
		return 0
	fi
}
if [ "$user" = "boot" ]; then
	cmclient -u "wifi_c1000" SET "$obj".Enable true
	exit 0
fi
if [ $# -ge 1 ]; then
	for arg; do # Arg list as separate words
		service_get "$obj.$arg"
	done
fi
if [ "$user" = "wifi_c1000" ]; then
	exit 0
fi
if [ "$changedEnable" != "1" ] && [ "$changedChannel" != "1" ] && [ "$init" != 1 ]; then
	if [ "$newEnable" = "false" ]; then
		exit 0
	fi
	relevantChange=0
	for i in Name SSIDReference LowerLayers AutoChannelEnable \
		Channel OperatingFrequencyBand OperatingStandards \
		X_ADB_nProtection GuardInterval \
		OperatingChannelBandwidth ExtensionChannel \
		X_ADB_STBC_Tx X_ADB_STBC_Rx RegulatoryDomain \
		IEEE80211hEnabled SSIDAdvertisementEnabled WMMEnable \
		UAPSDEnable X_ADB_MacMode X_ADB_MacList ModeEnabled \
		X_ADB_EncryptionMode RekeyingInterval PresharedKey \
		KeyPassphrase ConfigMethodsEnabled; do
		if [ "$(eval echo \$changed${i})" = "1" ]; then
			relevantChange=1
			break
		fi
	done
	if [ $relevantChange -eq 0 ]; then exit 0; fi
fi
case "$obj" in
"Device.WiFi.AccessPoint."*"."*)
	ap=${obj%\.*}
	ssid=$(cmclient GETV "$ap".SSIDReference)
	radio=$(cmclient GETV "$ssid".LowerLayers)
	;;
"Device.WiFi.AccessPoint."*)
	ssid=$(cmclient GETV "$obj".SSIDReference)
	radio=$(cmclient GETV "$ssid".LowerLayers)
	;;
"Device.WiFi.Radio."*)
	radio="$obj"
	;;
"Device.WiFi.SSID."*)
	radio=$(cmclient GETV "$obj".LowerLayers)
	;;
esac
if [ "$changedChannel" = "1" ]; then
	cmclient SET -u wifi_c1000 "$radio".X_ADB_SetChannel "$newChannel" 2>/dev/null
fi
ifn=$(cmclient GETV "$radio".Name)
if [ -f /tmp/hostapd_"$ifn".pid ]; then
	kill -9 $(cat /tmp/hostapd_"$ifn".pid) 2>/dev/null
fi
if [ $(cmclient GETV "$radio".Enable) = "false" ]; then
	for ssid in $(cmclient GETO Device.WiFi.SSID.[LowerLayers="$radio"]); do
		ap="$(cmclient GETO Device.WiFi.AccessPoint.[SSIDReference="$ssid"])"
		if [ "$(cmclient GETV "$ssid".Status)" != "Down" ] && [ "$init" != "1" ]; then
			cmclient SET -u wifi_c1000 "$ssid".Status Down 2>/dev/null
		fi
		if [ -n "$ap" ]; then
			if [ "$(cmclient GETV "$ap".Status)" != "Disabled" ] && [ "$init" != "1" ]; then
				cmclient SET -u wifi_c1000 "$ap".Status Disabled 2>/dev/null
			fi
		fi
	done
	if [ "$(cmclient GETV "$radio".Status)" != "Down" ] && [ "$init" != "1" ]; then
		cmclient SET -u wifi_c1000 "$radio".Status Down 2>/dev/null
	fi
	exit 0
fi
echo interface="$ifn" >/tmp/hostapd_"$ifn".conf
echo bridge=br0 >>/tmp/hostapd_"$ifn".conf # FIXME!
echo driver=nl80211 >>/tmp/hostapd_"$ifn".conf
if [ $(cmclient GETV "$radio".AutoChannelEnable) = "true" ]; then
	echo channel=0 >>/tmp/hostapd_"$ifn".conf
else
	if [ "$changedChannel" = "1" ]; then
		echo channel="$newChannel" >>/tmp/hostapd_"$ifn".conf
	else
		echo channel=$(cmclient GETV "$radio".Channel) >>/tmp/hostapd_"$ifn".conf
	fi
fi
if [ $(cmclient GETV "$radio".OperatingFrequencyBand) = "5GHz" ]; then
	echo hw_mode=a >>/tmp/hostapd_"$ifn".conf
elif [ -n $(expr $(cmclient GETV "$radio".OperatingStandards) : "[^g]*\(g\)[^g]*") ]; then
	echo hw_mode=g >>/tmp/hostapd_"$ifn".conf
else
	echo hw_mode=b >>/tmp/hostapd_"$ifn".conf
fi
if [ -n $(expr "$(cmclient GETV "$radio".OperatingStandards)" : "[^n]*\(n\)[^n]*") ]; then
	echo ieee80211n=1 >>/tmp/hostapd_"$ifn".conf
	if [ "$(cmclient GETV "$radio".OperatingStandards)" = "n" ]; then
		echo require_ht=1 >>/tmp/hostapd_"$ifn".conf
	fi
	echo -n ht_capab= >>/tmp/hostapd_"$ifn".conf
	if [ "$(cmclient GETV "$radio".X_ADB_nProtection)" = "true" ]; then
		echo -n [GF] >>/tmp/hostapd_"$ifn".conf
	fi
	if [ "$(cmclient GETV "$radio".GuardInterval)" != "800ns" ]; then
		echo -n [SHORT-GI-20][SHORT-GI-40] >>/tmp/hostapd_"$ifn".conf
	fi
	if [ "$(cmclient GETV "$radio".OperatingChannelBandwidth)" = "40MHz" ]; then
		echo -n [HT40 >>/tmp/hostapd_"$ifn".conf
		if [ "$(cmclient GETV "$radio".ExtensionChannel)" = "AboveControlChannel" ]; then
			echo -n "+]" >>/tmp/hostapd_"$ifn".conf
		else
			echo -n "-]" >>/tmp/hostapd_"$ifn".conf
		fi
	fi
	if [ "$(cmclient GETV "$radio".X_ADB_STBC_Tx)" = "true" ]; then
		echo -n [TX-STBC] >>/tmp/hostapd_"$ifn".conf
	fi
	if [ "$(cmclient GETV "$radio".X_ADB_STBC_Rx)" = "true" ]; then
		echo -n [RX-STBC1] >>/tmp/hostapd_"$ifn".conf
	fi
	echo >>/tmp/hostapd_"$ifn".conf
fi
regd="$(cmclient GETV "$radio".RegulatoryDomain)"
if [ -n "$regd" ]; then
	echo country_code="${regd%[IO ]}" >>/tmp/hostapd_"$ifn".conf
fi
if [ "$(cmclient GETV "$radio".IEEE80211hEnabled)" = "true" ]; then
	echo ieee80211h=1 >>/tmp/hostapd_"$ifn".conf
fi
ifn="$(cmclient GETV "$radio".Name)"
dev="${ifn%.*}"
phy="${dev##*[a-z]}"
echo -n "$(cmclient GETV "$radio".MCS)" >/sys/kernel/debug/ieee80211/phy"$phy"/rc/fixed_rate_idx
if [ "$(cmclient GETV "$radio".X_ADB_WMMGlobalNoAck)" = "true" ]; then
	echo 1 >/sys/kernel/debug/ieee80211/phy"$phy"/noack
else
	echo 0 >/sys/kernel/debug/ieee80211/phy"$phy"/noack
fi
ssidc=0
for ssid in $(cmclient GETO Device.WiFi.SSID.[LowerLayers="$radio"].[Enable=true]); do
	ap="$(cmclient GETO Device.WiFi.AccessPoint.[SSIDReference="$ssid"].[Enable=true])"
	if [ -z "$ap" ]; then
		continue
	fi
	if [ $ssidc -ne 0 ]; then
		echo bss="$(cmclient GETV "$ssid".Name)" >>/tmp/hostapd_"$ifn".conf
	fi
	echo ssid="$(cmclient GETV "$ssid".SSID)" >>/tmp/hostapd_"$ifn".conf
	echo bssid="$(cmclient GETV "$ssid".BSSID)" >>/tmp/hostapd_"$ifn".conf
	if [ "$(cmclient GETV "$ap".SSIDAdvertisementEnabled)" = "false" ]; then
		echo ignore_broadcast_ssid=2 >>/tmp/hostapd_"$ifn".conf
	fi
	echo max_num_sta="$(cmclient GETV "$ap".X_ADB_MaxAssocLimit)" >>/tmp/hostapd_"$ifn".conf
	if [ "$(cmclient GETV "$ap".X_ADB_WMMGlobalEnable)" = "true" ]; then # FIXME once done with the GUI.
		echo wmm_enabled=1 >>/tmp/hostapd_"$ifn".conf
	fi
	if [ "$(cmclient GETV "$ap".UAPSDEnable)" = "true" ]; then
		echo uapsd_advertisement_enabled=1 >>/tmp/hostapd_"$ifn".conf
	fi
	if [ "$(cmclient GETV "$ssid".X_ADB_MacMode)" = "Accept" ]; then
		echo macaddr_acl=0 >>/tmp/hostapd_"$ifn".conf
		echo >/tmp/hostapd_"$ifn"_accept
		for m in $(cmclient GETV "$ssid".X_ADB_MacList | tr "," " "); do
			echo "$m" >>/tmp/hostapd_"$ifn"_accept
		done
		echo accept_mac_file=/tmp/hostapd_"$ifn"_accept >>/tmp/hostapd_"$ifn".conf
	elif [ "$(cmclient GETV "$ssid".X_ADB_MacMode)" = "Deny" ]; then
		echo macaddr_acl=1 >>/tmp/hostapd_"$ifn".conf
		echo >/tmp/hostap_"$ifn"_deny
		for m in $(cmclient GETV "$ssid".X_ADB_MacList | tr "," " "); do
			echo "$m" >>/tmp/hostapd_"$ifn"_deny
		done
		echo accept_mac_file=/tmp/hostapd_"$ifn"_deny >>/tmp/hostapd_"$ifn".conf
	fi
	echo auth_algs=3 >>/tmp/hostapd_"$ifn".conf
	case $(cmclient GETV "$ap".Security.ModeEnabled) in
	"WEP-"*)
		echo wep_default_key=0 >>/tmp/hostapd_"$ifn".conf
		echo wep_key0="$(cmclient GETV "$ap".Security.WEPKey)" >>/tmp/hostapd_"$ifn".conf
		;;
	"WPA"*)
		echo wpa_key_mgmt=WPA-PSK >>/tmp/hostapd_"$ifn".conf
		case $(cmclient GETV "$ap".Security.X_ADB_EncryptionMode) in
		"TKIP")
			echo wpa_pairwise=TKIP >>/tmp/hostapd_"$ifn".conf
			;;
		"AES")
			echo wpa_pairwise=CCMP >>/tmp/hostapd_"$ifn".conf
			;;
		"TKIP-AES")
			echo wpa_pairwise=TKIP CCMP >>/tmp/hostapd_"$ifn".conf
			;;
		esac
		echo wpa_gmk_rekey="$(cmclient GETV "$ap".Security.RekeyingInterval)" >>/tmp/hostapd_"$ifn".conf
		if [ -n "$(cmclient GETV "$ap".Security.PreSharedKey)" ]; then
			echo wpa_psk="$(cmclient GETV "$ap".Security.PreSharedKey)" >>/tmp/hostapd_"$ifn".conf
		else
			echo wpa_passphrase="$(cmclient GETV "$ap".Security.KeyPassphrase)" >>/tmp/hostapd_"$ifn".conf
		fi
		;;
	esac
	case $(cmclient GETV "$ap".Security.ModeEnabled) in
	"WPA-Personal")
		echo wpa=1 >>/tmp/hostapd_"$ifn".conf
		;;
	"WPA2-Personal")
		echo wpa=2 >>/tmp/hostapd_"$ifn".conf
		;;
	"WPA-WPA2-Personal")
		echo wpa=3 >>/tmp/hostapd_"$ifn".conf
		;;
	esac
	if [ "$(cmclient GETV "$ap".WPS.Enable)" = "true" ]; then
		case $(cmclient GETV "$ap".Security.ModeEnabled) in
		*"None" | "WPA2-Personal" | "WPA-WPA2-Personal")
			echo wps_state=2 >>/tmp/hostapd_"$ifn".conf
			;;
		*)
			echo wps_state=1 >>/tmp/hostapd_"$ifn".conf
			;;
		esac
		echo -n config_methods= >>/tmp/hostapd_"$ifn".conf
		for i in $(cmclient GETV "$ap".WPS.ConfigMethodsEnabled | tr -d "," " "); do
			case "$i" in
			"PushButton") method="push_button" ;;
			"NFCInterface") method="nfc_interface" ;;
			"IntegratedNFCToken") method="int_nfc_token" ;;
			"ExternalNFCToken") method="ext_nfc_token" ;;
			"Ethernet") method="ethernet" ;;
			"USBFlashDrive") method="usba" ;;
			"PIN") method="display" ;;
			esac
			echo -n "$method " >>/tmp/hostapd_"$ifn".conf
		done
		echo >>/tmp/hostapd_"$ifn".conf
		echo device_name=$(cmclient GETV Device.DeviceInfo.ModelName) >>/tmp/hostapd_"$ifn".conf
		echo model_name=$(cmclient GETV Device.DeviceInfo.ModelName) >>/tmp/hostapd_"$ifn".conf
		echo manufacturer=$(cmclient GETV Device.DeviceInfo.Manufacturer) >>/tmp/hostapd_"$ifn".conf
		echo model_number=$(cmclient GETV Device.DeviceInfo.SerialNumber) >>/tmp/hostapd_"$ifn".conf
		echo serial_number=$(cmclient GETV Device.DeviceInfo.SerialNumber) >>/tmp/hostapd_"$ifn".conf
		echo device_type=6-$(cmclient GETV Device.DeviceInfo.ManufacturerOUI)04-1 >>/tmp/hostapd_"$ifn".conf
	fi
	ssidc=$((ssidc + 1))
done
hostapd -B -P /tmp/hostapd_"$ifn".pid /tmp/hostapd_"$ifn".conf
if [ $? -eq 0 ]; then
	for ssid in $(cmclient GETO Device.WiFi.SSID.[LowerLayers="$radio"].[Enable=true]); do
		ap="$(cmclient GETO Device.WiFi.AccessPoint.[SSIDReference="$ssid"].[Enable=true])"
		if [ "$(cmclient GETV "$ssid".Status)" != "Up" ]; then
			cmclient SET -u wifi_c1000 "$ssid".Status Up 2>/dev/null
		fi
		if [ -n "$ap" ]; then
			if [ "$(cmclient GETV "$ap".Status)" != "Enabled" ]; then
				cmclient SET -u wifi_c1000 "$ap".Status Enabled 2>/dev/null
			fi
		fi
		ap="$(cmclient GETO Device.WiFi.AccessPoint.[SSIDReference="$ssid"].[Enable=false])"
		if [ -n "$ap" ]; then
			if [ "$(cmclient GETV "$ap".Status)" != "Disabled" ]; then
				cmclient SET -u wifi_c1000 "$ap".Status Disabled 2>/dev/null
			fi
		fi
	done
	for ssid in $(cmclient GETO Device.WiFi.SSID.[LowerLayers="$radio"].[Enable=false]); do
		ap="$(cmclient GETO Device.WiFi.AccessPoint.[SSIDReference="$ssid"])"
		if [ "$(cmclient GETV "$ssid".Status)" != "Down" ]; then
			cmclient SET -u wifi_c1000 "$ssid".Status Down 2>/dev/null
		fi
		if [ -n "$ap" ]; then
			if [ "$(cmclient GETV "$ap".Status)" != "Disabled" ]; then
				cmclient SET -u wifi_c1000 "$ap".Status Disabled 2>/dev/null
			fi
		fi
	done
	if [ "$(cmclient GETV "$radio".Status)" != "Up" ]; then
		cmclient SET -u wifi_c1000 "$radio".Status Up 2>/dev/null
	fi
else
	for ssid in $(cmclient GETO Device.WiFi.SSID.[LowerLayers="$radio"].[Enable=true]); do
		ap="$(cmclient GETO Device.WiFi.AccessPoint.[SSIDReference="$ssid"].[Enable=true])"
		if [ "$(cmclient GETV "$ssid".Status)" != "Error" ]; then
			cmclient SET -u wifi_c1000 "$ssid".Status Error 2>/dev/null
		fi
		if [ -n "$ap" ]; then
			if [ "$(cmclient GETV "$ap".Status)" != "Error_Misconfigured" ]; then
				cmclient SET -u wifi_c1000 "$ap".Status Error_Misconfigured 2>/dev/null
			fi
		fi
		ap="$(cmclient GETO Device.WiFi.AccessPoint.[SSIDReference="$ssid"].[Enable=false])"
		if [ -n "$ap" ]; then
			if [ "$(cmclient GETV "$ap".Status)" != "Disabled" ]; then
				cmclient SET -u wifi_c1000 "$ap".Status Disabled 2>/dev/null
			fi
		fi
	done
	for ssid in $(cmclient GETO Device.WiFi.SSID.[LowerLayers="$radio"].[Enable=false]); do
		ap="$(cmclient GETO Device.WiFi.AccessPoint.[SSIDReference="$ssid"])"
		if [ "$(cmclient GETV "$ssid".Status)" != "Down" ]; then
			cmclient SET -u wifi_c1000 "$ssid".Status Down 2>/dev/null
		fi
		if [ -n "$ap" ]; then
			if [ "$(cmclient GETV "$ap".Status)" != "Disabled" ]; then
				cmclient SET -u wifi_c1000 "$ap".Status Disabled 2>/dev/null
			fi
		fi
	done
	if [ "$(cmclient GETV "$radio".Status)" != "Error" ]; then
		cmclient SET -u wifi_c1000 "$radio".Status Error 2>/dev/null
	fi
fi
exit 0
