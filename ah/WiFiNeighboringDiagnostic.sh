#!/bin/sh
AH_NAME="WiFiNeighboringDiagnostic"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize ${AH_NAME}
. /etc/ah/helper_functions.sh
. /etc/ah/helper_wlan.sh
. /etc/ah/target.sh
radio_scan_neighbors() {
	local ap_conf idx result_obj tmp setm_params radio_iface radio_obj="$1"
	local SSID InfrastructureMode RSSI SignalStrength Noise BSSID Standards \
		Channel FrequencyBand ChannelBandwidth ExtensionChannel SecurityMode \
		EncryptionMode DTIMPeriod BeaconPeriod BasicDataRates DataRates MaxPhyRate
	cmclient -v radio_iface GETV "$radio_obj.Name"
	if wifiradio_isup "$radio_iface"; then
		while IFS= read -r ap_conf; do
			[ -z "$ap_conf" ] && continue
			[ "$ap_conf" = "FAILED" ] && return 1
			SSID=""
			InfrastructureMode=""
			RSSI=""
			SignalStrength=""
			Noise=""
			BSSID=""
			Standards=""
			Channel=""
			FrequencyBand=""
			ChannelBandwidth=""
			ExtensionChannel=""
			SecurityMode=""
			EncryptionMode=""
			DTIMPeriod=""
			BeaconPeriod=""
			BasicDataRates=""
			DataRates=""
			MaxPhyRate=""
			eval $ap_conf
			RSSI=${RSSI%' dBm'}
			Noise=${Noise%' dBm'}
			InfrastructureMode=$(help_tr " " "" "$InfrastructureMode")
			Channel=${Channel%','*}
			cmclient -v idx ADD "$obj.Result.[BSSID=$BSSID]"
			result_obj="$obj.Result.$idx"
			cmclient SETM "$result_obj.SupportedStandards=$Standards"
			setm_params="$result_obj.Radio=$radio_obj"
			setm_params="$setm_params	$result_obj.SSID=$SSID"
			tmp=""
			case "$InfrastructureMode" in
			"Managed") tmp="Infrastructure" ;;
			"AdHoc") tmp="AdHoc" ;;
			esac
			[ -n "$tmp" ] && setm_params="$setm_params	$result_obj.Mode=$tmp"
			setm_params="$setm_params	$result_obj.Channel=$Channel"
			setm_params="$setm_params	$result_obj.X_ADB_ExtensionChannel=$ExtensionChannel"
			setm_params="$setm_params	$result_obj.SignalStrength=$RSSI"
			tmp=""
			case "$SecurityMode" in
			"WEP") tmp="WEP" ;;
			"OPEN") tmp="None" ;;
			"WPA") tmp="WPA-Enterprise" ;;
			"WPA2") tmp="WPA2-Enterprise" ;;
			"WPAWPA2") tmp="WPA-WPA2-Enterprise" ;;
			"WPAPSK") tmp="WPA" ;;
			"WPA2PSK") tmp="WPA2" ;;
			"WPAWPA2PSK") tmp="WPA-WPA2" ;;
			esac
			[ -n "$tmp" ] && setm_params="$setm_params	$result_obj.SecurityModeEnabled=$tmp"
			setm_params="$setm_params	$result_obj.EncryptionMode=$EncryptionMode"
			setm_params="$setm_params	$result_obj.OperatingFrequencyBand=$FrequencyBand"
			setm_params="$setm_params	$result_obj.OperatingStandards=$Standards"
			setm_params="$setm_params	$result_obj.OperatingChannelBandwidth=$ChannelBandwidth"
			[ -n "$BeaconPeriod" ] && setm_params="$setm_params	$result_obj.BeaconPeriod=$BeaconPeriod"
			setm_params="$setm_params	$result_obj.Noise=$Noise"
			setm_params="$setm_params	$result_obj.BasicDataTransferRates=$BasicDataRates"
			setm_params="$setm_params	$result_obj.SupportedDataTransferRates=$DataRates"
			[ -n "$DTIMPeriod" ] && setm_params="$setm_params	$result_obj.DTIMPeriod=$DTIMPeriod"
			tmp=""
			case "$SignalStrength" in
			1) tmp="NoSignal" ;;
			2) tmp="VeryLow" ;;
			3) tmp="Low" ;;
			4) tmp="Good" ;;
			5) tmp="VeryGood" ;;
			6) tmp="Excellent" ;;
			esac
			[ -n "$tmp" ] && setm_params="$setm_params	$result_obj.X_ADB_SignalQuality=$tmp"
			[ -n "$MaxPhyRate" ] && setm_params="$setm_params	$result_obj.X_ADB_MaxPhyRate=$MaxPhyRate"
			cmclient SETM "$setm_params"
		done <<-EOF
			$(wifi_scan_ap "$radio_iface" 300 || echo FAILED)
		EOF
	fi
	return 0
}
diagnostic_run() {
	local radios radio_obj pid scan_pids="" final_state
	cmclient DEL "$obj.Result"
	cmclient SET "$obj.X_ADB_LastScanTime" "$(date -u +%FT%TZ)"
	cmclient -v radios GETO Device.WiFi.Radio.[Enable=true]
	for radio_obj in $radios; do
		radio_scan_neighbors "$radio_obj" &
		echo "$!" >>"/tmp/${AH_NAME}.pid2"
		scan_pids="$scan_pids $!"
	done
	final_state="Complete"
	for pid in $scan_pids; do
		wait "$pid" || final_state="Error"
	done
	cmclient SETE $obj.DiagnosticsState $final_state
	rm -f "/tmp/${AH_NAME}.pid" "/tmp/${AH_NAME}.pid2"
}
diagnostic_stop() {
	local pidfile="/tmp/${AH_NAME}.pid" pid
	if [ -e "$pidfile" ]; then
		read -r pid <${pidfile}
		kill $pid
		while read -r pid; do
			kill $pid
		done <${pidfile}2
		rm -f ${pidfile} ${pidfile}2
	fi
}
diagnostic_set() {
	case "$newDiagnosticsState" in
	Requested)
		diagnostic_stop
		diagnostic_run &
		echo "$!" >>"/tmp/${AH_NAME}.pid"
		;;
	Canceled)
		[ "$oldDiagnosticsState" = "Requested" ] || exit 1
		diagnostic_stop
		cmclient SETE $obj.DiagnosticsState None
		;;
	*)
		exit 1
		;;
	esac
}
case "$op" in
s)
	[ "$setDiagnosticsState" = "1" ] && diagnostic_set
	;;
esac
exit 0
