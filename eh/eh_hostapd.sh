#!/bin/sh
#udp:*,hostap,*
#sync:max=3
. /etc/ah/helper_serialize.sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_wlan.sh
. /etc/ah/target.sh
get_ifname_list() {
	[ "$2" != "ifnames" ] && local ifnames
	cmclient -v ifnames GETV "Device.WiFi.SSID.[SSID=$1].Name"
	if [ ${#ifnames} -eq 0 -a -n "$3" ]; then
		cmclient -v ifnames GETV "Device.WiFi.SSID.[SSID=$1,$3].Name"
	fi
	eval $2="'$ifnames'"
}
kill_ap_still_on() {
	local apobj ifname
	cmclient -v apobj GETO "Device.WiFi.AccessPoint.WPS.[X_ADB_Status=Ongoing]"
	for apobj in $apobj; do
		apobj=${apobj%.*}
		cmclient -v ifname GETV "%($apobj.SSIDReference).Name"
		wps_triggered_actions "wps_off" "$ifname"
	done
}
wps_triggered_actions() {
	local k ssid ap apstatus wpsstatus
	for k in $2; do
		cmclient -v ssid GETO "Device.WiFi.SSID.[Name=${k}]"
		cmclient -v ap GETO "Device.WiFi.AccessPoint.[SSIDReference=${ssid}]"
		cmclient -v apstatus GETV "$ap.Status"
		cmclient -v wpsstatus GETV "$ap.WPS.X_ADB_Status"
		cmclient -v wpsenable GETV "$ap.WPS.Enable"
		cmclient -v factoryMode GETV "Device.X_ADB_FactoryData.FactoryMode"
		if [ "$wpsstatus" = "Ongoing" ]; then
			if [ "$apstatus" = "Enabled" ]; then
				case $1 in
				"wps_off")
					cmclient SET -u "WiFiAP${ap}.WPS" "${ap}.WPS.X_ADB_Status" Disabled
					WPS_STATE=$(/usr/sbin/hostapd_cli -p /var/run/hostapd-$k/ wps_pbc_state $k)
					case $WPS_STATE in
					"ON")
						/usr/sbin/hostapd_cli -p /var/run/hostapd-$k/ wps_cancel $k
						;;
					esac
					;;
				"wps_error")
					cmclient SET -u "WiFiAP${ap}.WPS" "${ap}.WPS.X_ADB_Status" Error
					;;
				"wps_overlap")
					cmclient SET -u "WiFiAP${ap}.WPS" "${ap}.WPS.X_ADB_Status" Error_Overlap
					;;
				"wps_done")
					cmclient SET -u "WiFiAP${ap}.WPS" "${ap}.WPS.X_ADB_Status" Completed
					;;
				esac
			else
				cmclient SET -u "WiFiAP${ap}.WPS" "${ap}.WPS.X_ADB_Status" Disabled
			fi
		elif [ "$factoryMode" != "true" ]; then
			if [ "$wpsenable" = "false" -o "$apstatus" != "Enabled" ]; then
				cmclient SET -u "WiFiAP${ap}.WPS" "${ap}.WPS.X_ADB_Status" Disabled
			fi
		fi
	done
}
assoc_dev_add() {
	local ifname=$1 sta_addr=$2 radioObj radioName ap ssidmatch apmatch adid assocHostsObj
	help_serialize "$1_$2" notrap
	cmclient -v radioObj GETV "Device.WiFi.SSID.[Name=$ifname].LowerLayers"
	cmclient -v radioName GETV "$radioObj.Name"
	cmclient -v ssidmatch GETO "Device.WiFi.SSID.[Name=$ifname].[LowerLayers=$radioObj]"
	update_pcie_aspm_status $radioName
	for ssid in $ssidmatch; do
		cmclient -v apmatch GETO "Device.WiFi.AccessPoint.[SSIDReference=$ssid]"
		for ap in $apmatch; do
			cmclient -v adid GETO "$ap.AssociatedDevice.[MACAddress=$sta_addr]"
			if [ -n "$adid" ]; then
				adid=${adid##*.}
			else
				cmclient -v adid ADD $ap.AssociatedDevice
				cmclient SET $ap.AssociatedDevice.$adid.MACAddress $sta_addr
			fi
			cmclient -v assocHostsObj GETO "Device.Hosts.Host.*.[PhysAddress=$sta_addr]"
			if [ -n "$assocHostsObj" ]; then
				cmclient SET $assocHostsObj.AssociatedDevice $ap.AssociatedDevice.$adid
			fi
			station_sta=$(hostapd_cli -p /var/run/hostapd-${radioName} sta_status ${sta_addr})
			cmclient -v secMode GETV "$ap".Security.ModeEnabled
			case $secMode in
			*)
				case $station_sta in
				"STA Associated"* | "STA Authenticated"*)
					cmclient SET $ap.AssociatedDevice.$adid.AuthenticationState false
					;;
				"STA Authorized"*)
					cmclient SET $ap.AssociatedDevice.$adid.AuthenticationState true
					;;
				"FAIL"*)
					cmclient SET $ap.AssociatedDevice.$adid.AuthenticationState false
					;;
				esac
				;;
			esac
		done
	done
	help_serialize_unlock "$1_$2"
}
assoc_dev_del() {
	local ifname=$1 sta_addr=$2 radioObj radioName a ssidmatch apmatch adid assocdiag
	cmclient -v radioObj GETV "Device.WiFi.SSID.[Name=$ifname].LowerLayers"
	cmclient -v radioName GETV "$radioObj.Name"
	update_pcie_aspm_status $radioName
	cmclient -v ssidmatch GETO "Device.WiFi.SSID.[LowerLayers=$radioObj].[Name=$ifname]"
	for ssid in $ssidmatch; do
		cmclient -v apmatch GETO "Device.WiFi.AccessPoint.[SSIDReference=$ssid]"
		for ap in $apmatch; do
			cmclient -v adid GETO "$ap.AssociatedDevice.[MACAddress=$sta_addr]"
			for a in $adid; do
				cmclient DEL $a
			done
		done
		cmclient -v assocdiag GETO "Device.WiFi.X_ADB_AssociatedDevicesDiagnostics.1.AssociatedDevice.[MACAddress=$sta_addr].[SSID=$ssid]"
		[ ${#assocdiag} -gt 0 ] && cmclient DEL $assocdiag
	done
}
awake_ppp_onclient() {
	local __pppOnClient pppOnClient
	cmclient -v pppOnClient GETO "Device.PPP.Interface.[Enable=true].[ConnectionStatus!Connected].[ConnectionTrigger=X_ADB_OnClient]"
	for __pppOnClient in ${pppOnClient}; do
		cmclient SET "${__pppOnClient}.X_ADB_Reconnect" "true"
	done
}
acl_reject_add_assocdev() {
	local assoc_mac current_mac_list ssid ifname=$1 mac=$2
	cmclient -v ssid GETO "Device.WiFi.SSID.[Name=$ifname]"
	cmclient -v ap GETO "Device.WiFi.AccessPoint.[SSIDReference=$ssid]"
	cmclient -v current_mac_list GETV "$ap.AssociatedDevice.*.MACAddress"
	for assoc_mac in $current_mac_list; do
		if [ "$assoc_mac" = "$mac" ]; then
			return
		fi
	done
	cmclient -v AD_entry ADD "$ap.AssociatedDevice"
	cmclient SET "$ap.AssociatedDevice.$AD_entry.MACAddress" "$mac"
	cmclient SET "$ap.AssociatedDevice.$AD_entry.AuthenticationState" "false"
	log_num="003 - "
	log_msg="AssociatedDevice: denied client MacAddr=\"$mac\""
}
set_is_old_assoc_sta() {
	local assoc_mac current_mac_list assoc_obj ssid ap ifname=$1 mac=$2
	cmclient -v ssid GETO "Device.WiFi.SSID.[Name=$ifname]"
	cmclient -v ap GETO "Device.WiFi.AccessPoint.[SSIDReference=$ssid]"
	cmclient -v current_mac_list GETV "$ap.AssociatedDevice.*.MACAddress"
	for assoc_mac in $current_mac_list; do
		if [ "$assoc_mac" = "$mac" ]; then
			cmclient -v assoc_obj GETO "$ap.AssociatedDevice.*.[MACAddress=$assoc_mac]"
			cmclient SET "$assoc_obj.AuthenticationState" "true"
		fi
	done
}
set_deauth_status() {
	local assoc_obj ifname=$1 mac=$2
	cmclient -v ssid GETO "Device.WiFi.SSID.[Name=$ifname]"
	cmclient -v ap GETO "Device.WiFi.AccessPoint.[SSIDReference=$ssid]"
	cmclient -v assoc_obj GETO "$ap.AssociatedDevice.*.[MACAddress=$mac]"
	cmclient -u TIHosts SET "$assoc_obj.AuthenticationState" "false"
}
manage_bsd_when_channel_switch() {
	local eventObj= i= setm_params=
	cmclient SET 'Device.WiFi.X_ADB_BandSteering.Status' 'Error_RadioOff'
	[ -e "$bsdConfTempFile" ] && rm "$bsdConfTempFile"
	[ -e "$bsdConf" ] && rm "$bsdConf"
	cmclient DEL 'Device.X_ADB_Time.Event.[Alias=WiFi_BSD_Restart]'
	cmclient -v i ADDE 'Device.X_ADB_Time.Event.[Alias=WiFi_BSD_Restart]'
	eventObj="Device.X_ADB_Time.Event.$i"
	cmclient -v i ADDE "$eventObj.Action"
	setm_params="$eventObj.Alias=WiFi_BSD_Restart"
	setm_params="$setm_params	$eventObj.Type=Aperiodic"
	setm_params="$setm_params	$eventObj.DeadLine=60"
	setm_params="$setm_params	$eventObj.Action.$i.Operation=Set"
	setm_params="$setm_params	$eventObj.Action.$i.Path=Device.WiFi.X_ADB_BandSteering.Reset"
	setm_params="$setm_params	$eventObj.Action.$i.Value=true"
	cmclient SETEM "$setm_params"
	cmclient SET "$eventObj.Enable" 'true'
}
case $A1 in
"wps_ongoing")
	get_ifname_list "$A2" ifnamelist "$A3"
	;;
"wps_off")
	get_ifname_list "$A2" ifnamelist "$A3"
	;;
"wps_error")
	get_ifname_list "$A2" ifnamelist "$A3"
	;;
"wps_done")
	get_ifname_list "$A2" ifnamelist "$A3"
	;;
"wps_overlap")
	get_ifname_list "$A2" ifnamelist "$A3"
	;;
"wps_deinit") ;;

"wps_reset")
	ifnamelist="$A2"
	;;
*)
	ifnamelist="$A2"
	;;
esac
log_preamble="Wi-Fi[$ifnamelist]"
log_identity="hostapd"
log_prio=4
log_prefix="Wi-Fi"
case $A1 in
"assoc")
	log_msg="Association: detected client MAC MacAddr=\"$A3\""
	log_num="004 - "
	cmclient -v found GETO "Device.Hosts.Host.[PhysAddress=$A3].[Layer1Interface>Ethernet]"
	if [ -n "$found" ]; then
		mac=$(help_tr ":" "" "$A3")
		while read _ entry _ _ mask; do
			if [ -n "$entry" -a "$entry" = "$mac" ]; then
				echo $mac 0 0 $mask 0 >/proc/hwswitch/default/arl
				break
			fi
		done </proc/hwswitch/default/arltable
	fi
	assoc_dev_add "$A2" "$A3"
	awake_ppp_onclient
	;;
"dualband")
	local dual_defined="" video_defined="" single_defined=""
	[ ! -x "/usr/sbin/bsd" ] && exit 0
	cmclient -v dual_defined GETV Device.WiFi.X_ADB_BandSteering.DualBandSTA
	cmclient -v video_defined GETV Device.WiFi.X_ADB_BandSteering.VideoSTA
	cmclient -v single_defined GETV Device.WiFi.X_ADB_BandSteering.SingleBandSTA
	case ,$dual_defined,$video_defined,$single_defined, in
	*,"$A3",*) ;;

	*)
		cmclient SETE Device.WiFi.X_ADB_BandSteering.DualBandSTA ${dual_defined:+$dual_defined,}$A3
		if pidof bsd; then
			cmclient SET Device.WiFi.X_ADB_BandSteering.Reset "true"
		fi
		;;
	esac
	log_msg="DualBand: client MacAddr=\"$A3\""
	log_num="075 - "
	;;
"disassoc")
	log_msg="Association: disconnected client MacAddr=\"$A3\""
	log_num="005 - "
	assoc_dev_del "$A2" "$A3"
	cmclient -v ssid_obj GETO "Device.WiFi.SSID.[Name=$A2]"
	help_align_host_table "$ssid_obj" "$A3"
	;;
"wpa_auth_completed")
	log_msg="Association: authenticated client MacAddr=\"$A3\""
	log_num="006 - "
	;;
"wpa_auth_terminated")
	log_msg="Association: deauthenticated client MacAddr=\"$A3\""
	log_num="007 - "
	;;
"wpa_auth_fail")
	log_msg="Association: new client attempted to connect MacAddr=\"$A3\""
	log_num="008 - "
	logger -t "hostapd" -p 3 "WPA authentication failed for STA MacAddr=\"$A3\" "
	;;
"acl_reject")
	log_msg="Association: denied client MacAddr=\"$A3\""
	log_num="003 - "
	;;
"wps_off")
	wps_triggered_actions "$A1" "$ifnamelist"
	kill_ap_still_on
	;;
"wps_done")
	wps_triggered_actions "$A1" "$ifnamelist"
	;;
"wps_ongoing")
	for k in $ifnamelist; do
		cmclient -v SSID GETO "Device.WiFi.SSID.[Name=${k}]"
		cmclient -v AP GETO "Device.WiFi.AccessPoint.[SSIDReference=${SSID}]"
		cmclient -v APSTATUS GETV "$AP.Status"
		if [ "$APSTATUS" = "Enabled" ]; then
			cmclient SET -u "WiFiAP${AP}.WPS" "${AP}.WPS.X_ADB_Status" Ongoing
		fi
	done
	;;
"wps_error")
	wps_triggered_actions "$A1" "$ifnamelist"
	;;
"wps_overlap")
	wps_triggered_actions "$A1" "$ifnamelist"
	;;
"wps_configured")
	cmclient -v SSID GETO "Device.WiFi.SSID.[Name=$A2]"
	cmclient -v AP GETO "Device.WiFi.AccessPoint.[SSIDReference=${SSID}]"
	case $A3 in "1") auth="None" ;; "2") auth="WPA-Personal" ;; "32") auth="WPA2-Personal" ;; "34") auth="WPA-WPA2-Personal" ;; *) auth="" ;; esac
	case $A4 in "4") encr="TKIP" ;; "8") encr="AES" ;; "12") encr="TKIP-AES" ;; *) encr="" ;; esac
	if [ "$auth" = "WPA-Personal" -a "$encr" = "TKIP" ]; then
		cmclient -v _ms GETV "${AP}.Security.ModesSupported"
		! help_is_in_list "$_ms" "WPA-Personal" && help_is_in_list "$_ms" "WPA-WPA2-Personal" && auth="WPA-WPA2-Personal"
		cmclient -v _ms GETV "${AP}.Security.X_ADB_EncryptionModesSupported"
		! help_is_in_list "$_ms" "TKIP" && help_is_in_list "$_ms" "TKIP-AES" && encr="TKIP-AES"
	fi
	[ ${#auth} -gt 0 ] && setm="${AP}.Security.ModeEnabled=${auth}"
	[ ${#encr} -gt 0 ] && setm="${setm:+$setm	}${AP}.Security.X_ADB_EncryptionMode=${encr}"
	[ ${#A5} -gt 0 ] && setm="${setm:+$setm	}${SSID}.SSID=$A5"
	[ "$auth" = None ] || setm="${setm:+$setm	}${AP}.Security.KeyPassphrase=$A6"
	setm="$setm	${AP}.Enable=true"
	cmclient -v _rn GETV "%($SSID.LowerLayers).Name"
	[ "$_rn" = "$A2" ] && cmclient SETEM "$setm" || cmclient SETM "$setm"
	cmclient -u "notstart" SET "${AP}.WPS.X_ADB_ConfigurationState Configured"
	cmclient SAVE
	;;
"wps_reset")
	wps_triggered_actions "wps_off" "$ifnamelist"
	;;
"asc_auto_ch")
	if [ -n "$A2" -a -n "$A3" ]; then
		cmclient -v Radio GETO "Device.WiFi.Radio.[Name=$A2]"
		if [ -n "${Radio}" ]; then
			_setm="${Radio}.Channel=$A3"
			if [ -n "$A6" ]; then
				_setm="$_setm	${Radio}.X_ADB_ChannelSwitchReason=$A6	${Radio}.X_ADB_LastChannelSwitchTime="$(date -u +%FT%TZ)
				if [ "$A6" = "DFS" ]; then
					cmclient -v counter GETV "${Radio}.X_ADB_RadarSwitchCount"
					counter=$((counter + 1))
					_setm="$_setm	${Radio}.X_ADB_RadarSwitchCount=$counter"
				fi
				if [ -x "/usr/sbin/bsd" ]; then
					cmclient -v op_band GETV "${Radio}.OperatingFrequencyBand"
					cmclient -v bsd_enabled GETV "Device.WiFi.X_ADB_BandSteering.Enable"
					[ "$bsd_enabled" = "true" -a "$A3" -gt 48 -a "$op_band" = "5GHz" ] && manage_bsd_when_channel_switch "$A2" "$A3"
				fi
			fi
			cmclient SETEM "$_setm"
		fi
		log_num="010 - "
		logger -t "$log_identity" -p 4 "$log_prefix" "$log_num" "$log_preamble: channel change: $A3"
	fi
	;;
"interf_sw_cnt")
	if [ -n "$A2" -a -n "$A3" ]; then
		cmclient -v Radio GETO "Device.WiFi.Radio.[Name=$A2]"
		[ -n "${Radio}" -a -n "$A3" ] && cmclient SETE "${Radio}.X_ADB_InterferenceSwitchCount $A3"
	fi
	;;
"chanim_state")
	if [ ${#A2} -gt 0 -a ${#A3} -gt 0 ]; then
		cmclient -v Radio GETO "Device.WiFi.Radio.[Name=$A2]"
		[ ${#Radio} -gt 0 -a ${#A3} -gt 0 ] && cmclient SETE "${Radio}.X_ADB_ChanimState $A3"
	fi
	;;
esac
[ -n "$log_msg" ] && logger -t "$log_identity" -p 4 "$log_prefix" "$log_num" "$log_preamble: $log_msg $A3" -p $log_prio
exit 0
