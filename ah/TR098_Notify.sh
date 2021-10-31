#!/bin/sh
AH_NAME="TR098_Notify"
[ "$user" = "tr098" ] && exit 0
service_notify_tr098() {
	local tr098_ref= p= ap_status= ssid_status= _tr098val=
	case "$obj" in
	"Device.WiFi.SSID"*)
		if [ "$changedEnable" = "1" ]; then
			cmclient -v tr098_ref GETV "$obj".X_ADB_TR098Reference
			p="${tr098_ref}.RadioEnabled=${newEnable}"
			p="${p}	${tr098_ref}.Enable=${newEnable}"
			cmclient SETEM "${p}"
		fi
		if [ "$changedStatus" = "1" ] && [ "$newStatus" != "Down" -o "$oldStatus" != "LowerLayerDown" ]; then
			cmclient -v tr098_ref GETV "$obj".X_ADB_TR098Reference
			cmclient -v ap_status GETV "Device.WiFi.AccessPoint.[SSIDReference=$obj].Status"
			ssid_status="$newStatus"
			if [ "$ssid_status" = "Up" -a "$ap_status" = "Enabled" ]; then
				_tr098val="Up"
			else
				_tr098val="Disabled"
			fi
			cmclient -u "cm181" SET "$tr098_ref.Status" "$_tr098val"
		fi
		;;
	"Device.WiFi.AccessPoint."*".Security")
		cmclient -v tr098_ref GETV "${obj%%.Security}".X_ADB_TR098Reference
		if [ "$changedModeEnabled" = "1" ]; then
			case "$newModeEnabled" in
			"None")
				p="${tr098_ref}.BasicEncryptionModes=None"
				p="${p}	${tr098_ref}.BeaconType=None"
				p="${p}	${tr098_ref}.WEPEncryptionLevel=Disabled"
				cmclient SETEM "${p}"
				;;
			"WEP-64")
				p="${tr098_ref}.BasicEncryptionModes=WEPEncryption"
				p="${p}	${tr098_ref}.BeaconType=Basic"
				p="${p}	${tr098_ref}.WEPEncryptionLevel=40-bit"
				cmclient SETEM "${p}"
				;;
			"WEP-128")
				p="${tr098_ref}.BasicEncryptionModes=WEPEncryption"
				p="${p}	${tr098_ref}.BeaconType=Basic"
				p="${p}	${tr098_ref}.WEPEncryptionLevel=104-bit"
				cmclient SETEM "${p}"
				;;
			"WPA-Personal")
				p="${tr098_ref}.BeaconType=WPA"
				p="${p}	${tr098_ref}.WEPEncryptionLevel=Disabled"
				cmclient SETEM "${p}"
				;;
			"WPA2-Personal")
				p="${tr098_ref}.BeaconType=11i"
				p="${p}	${tr098_ref}.WEPEncryptionLevel=Disabled"
				cmclient SETEM "${p}"
				;;
			"WPA-WPA2-Personal")
				p="${tr098_ref}.BeaconType=WPAand11i"
				p="${p}	${tr098_ref}.WEPEncryptionLevel=Disabled"
				cmclient SETEM "${p}"
				;;
			esac
		fi
		if [ "$setX_ADB_EncryptionMode" = "1" ]; then
			[ ${#newModeEnable} -eq 0 ] && cmclient -v newModeEnabled GETV "${obj}".ModeEnabled
			case "$newX_ADB_EncryptionMode" in
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
			case "$newModeEnabled" in
			None) p="${tr098_ref}.BasicEncryptionModes=None" ;;
			WEP*) p="${tr098_ref}.BasicEncryptionModes=WEPEncryption" ;;
			WPA-*) p="${tr098_ref}.WPAEncryptionModes=$_tr098val" ;;
			*) p="${tr098_ref}.IEEE11iEncryptionModes=$_tr098val" ;;
			esac
			cmclient SETEM "${p}"
		fi
		;;
	"Device.WiFi.AccessPoint"*)
		if [ "$changedStatus" = "1" ] && [ "$newStatus" != "Down" -o "$oldStatus" != "LowerLayerDown" ]; then
			ap_status="$newStatus"
			cmclient -v ssid_status GETV "%($obj.SSIDReference).Status"
			cmclient -v tr098_ref GETV "$obj.X_ADB_TR098Reference"
			if [ "$ssid_status" = "Up" -a "$ap_status" = "Enabled" ]; then
				_tr098val="Up"
			else
				_tr098val="Disabled"
			fi
			cmclient -u "cm181" SET "$tr098_ref.Status" "$_tr098val"
		fi
		;;
	"Device.WiFi.Radio"*)
		if [ "$changedOperatingStandards" = "1" ]; then
			cmclient -v tr098_ref GETV "$obj".X_ADB_TR098Reference
			case "$newOperatingStandards" in
			"g")
				_tr098val="g-only"
				;;
			"g,n" | "n,g" | "b,g,n" | "b,n,g" | "g,b,n" | "g,n,b" | \
				"n,b,g" | "n,g,b")
				_tr098val="n"
				;;
			"b,g" | "g,b")
				_tr098val="g"
				;;
			"a" | "b")
				_tr098val="$newOperatingStandards"
				;;
			esac
			cmclient SETE "${tr098_ref}.Standard" "$_tr098val"
		fi
		;;
	"Device.IP.Diagnostics"*)
		if [ "$changedDiagnosticsState" = "1" ]; then
			test=${obj##*.}
			test=${test%Diagnostics}
			tr098_ref="InternetGatewayDevice.${test}Diagnostics"
			cmclient -u "cm181" SETE \
				"${tr098_ref}.DiagnosticsState" \
				"$newDiagnosticsState"
		fi
		;;
	"Device.IP.Interface."*"IPv4Address"*)
		if [ "$changedIPAddress" = "1" ]; then
			_tr098val="$newIPAddress"
			cmclient -v tr098_ref GETV "$obj".X_ADB_TR098Reference
			case "$tr098_ref" in
			*"LANDevice"*)
				cmclient SETE "${tr098_ref}.IPInterfaceIPAddress" "$_tr098val"
				;;
			*"WANDevice"*)
				cmclient SETE "${tr098_ref}.ExternalIPAddress" "$_tr098val"
				;;
			esac
		fi
		if [ "$changedSubnetMask" = "1" ]; then
			_tr098val="$newSubnetMask"
			cmclient -v tr098_ref GETV "$obj".X_ADB_TR098Reference
			case "$tr098_ref" in
			*"LANDevice"*)
				cmclient SETE "${tr098_ref}.IPInterfaceSubnetMask" "$_tr098val"
				;;
			*"WANDevice"*)
				cmclient SETE "${tr098_ref}.SubnetMask" "$_tr098val"
				;;
			esac
		fi
		if [ "$changedAddressingType" = "1" ]; then
			_tr098val="$newAddressingType"
			cmclient -v tr098_ref GETV "$obj".X_ADB_TR098Reference
			case "$tr098_ref" in
			*"LANDevice"*)
				cmclient SETE "${tr098_ref}.IPInterfaceAddressingType" "$_tr098val"
				;;
			*"WANDevice"*)
				cmclient SETE "${tr098_ref}.AddressingType" "$_tr098val"
				;;
			esac
		fi
		;;
	"Device.X_ADB_DMZ"*)
		if [ "$changedInterface" = "1" ]; then
			cmclient -v _tr098val GETV "$newInterface".X_ADB_TR098Reference
			cmclient SETE "InternetGatewayDevice.X_ADB_DMZ.Interface" "$_tr098val"
		fi
		;;
	esac
}
case "$op" in
s)
	service_notify_tr098
	;;
esac
exit 0
