#!/bin/sh
AH_NAME="X_DLink_BandSteering.sh"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
get_client_band_steering_status() {
	local obj="$1" result=$2 client_mac_address="" client_steerable="" client_5ghz="" status="No action"
	cmclient -v client_mac_address GETV "$obj.AssociatedDeviceMACAddress"
	cmclient -v client_steerable GETO "Device.WiFi.X_ADB_BandSteering.[DualBandSTA,$client_mac_address]"
	cmclient -v client_5ghz GETO "Device.WiFi.X_ADB_BandSteering.[VideoSTA,$client_mac_address]"
	if [ ${#client_steerable} -ne 0 ]; then
		status="Steerable"
	elif [ ${#client_5ghz} -ne 0 ]; then
		status="5GHz only"
	fi
	eval $result="'$status'"
}
service_get() {
	local obj="$1" arg="$2" value=""
	get_client_band_steering_status "$obj" value
	cmclient SETE "$obj.$arg $value" >/dev/null
	echo "$value"
}
case "$op" in
g)
	for arg; do # arg list as separate words
		service_get "$obj" "$arg"
	done
	;;
esac
exit 0
