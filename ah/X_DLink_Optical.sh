#!/bin/sh
. /etc/ah/helper_functions.sh
AH_NAME="X_DLink_Optical.sh"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
service_get() {
	local obj="$1" arg="$2" vendor_name value serial_number serial_number_offset serial_number_len
	case "$arg" in
	VendorTechName)
		vendor_name=$(sfptool 0 0 20)
		case "$vendor_name" in
		ALCATEL*)
			serial_number_offset=42
			serial_number_len=20
			serial_number="$(sfptool 0 0 96)"
			serial_number="${serial_number:$serial_number_offset:$serial_number_len}"
			value=$(help_hex_to_string "$serial_number")
			;;
		HUAWEI*)
			serial_number_offset=210
			serial_number_len=16
			serial_number="$(sfptool 0 1 128)"
			serial_number="${serial_number:$serial_number_offset:$serial_number_len}"
			value=$(help_uppercase "$serial_number")
			;;
		*)
			value="N/A"
			;;
		esac
		;;
	TransmitOpticalLevel)
		help_convert_to_dbm "$(sfptool 0 1 102 -m)" value
		;;
	OpticalSignalLevel)
		help_convert_to_dbm "$(sfptool 0 1 104 -m)" value
		;;
	Status)
		cmclient -v value GETV "Device.Optical.Interface.1.Status"
		;;
	esac
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
