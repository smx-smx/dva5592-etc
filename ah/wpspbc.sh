#!/bin/sh

. /etc/ah/helper_functions.sh
. /etc/ah/helper_radio_toogle.sh

wps_trigger() {
	local main_ap_only="$1" ap ap_filter ssid ssid_name radio radio_name cmquery=

	ap_filter='None|WPA2-Personal'
	ap_filter="[Enable=true].[SSIDAdvertisementEnabled=true].[WPS.Enable=true].[WPS.ConfigMethodsEnabled,PushButton].[Security.ModeEnabled<$ap_filter]"

	cmclient -v ap GETO "Device.WiFi.AccessPoint.$ap_filter"
	for ap in $ap; do
		cmclient -v ssid GETV "$ap.SSIDReference"
		cmclient -v ssid GETO "$ssid.[Enable=true]"
		[ -z "$ssid" ] && continue

		cmclient -v radio GETV "$ssid.LowerLayers"
		cmclient -v radio GETO "$radio.[Enable=true]$cmquery"
		[ -z "$radio" ] && continue
		cmclient -v ssid_name GETV "$ssid.Name"
		cmclient -v radio_name GETV "$radio.Name"
		[ -n "$main_ap_only" -a "$ssid_name" != "$radio_name" ] && continue

		cmquery="$cmquery.[Name!${radio_name%.*}]"
		echo "[$radio_name] PBC WPS started on SSID $ssid_name"
		/usr/sbin/hostapd_cli -p "/var/run/hostapd-$radio_name" wps_pbc "$ssid_name"
	done

	[ -z "$cmquery" ] && echo "No AP is configured for PBC WPS"
}

radio_toggle() {
	local enable

	cmclient -v enable GETV Device.WiFi.X_ADB_Enable
	if [ "$enable" = "false" ]; then
		can_enable_main && cmclient SET Device.WiFi.X_ADB_Enable "true"
	else
		cmclient SET Device.WiFi.X_ADB_Enable "false"
	fi
}

case $1 in
"wps")
	wps_trigger
	;;
"radio")
	radio_toggle
	;;
*)
	echo "Invalid arguments"
	exit 1
	;;
esac
exit 0
