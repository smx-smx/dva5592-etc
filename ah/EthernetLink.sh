#!/bin/sh
AH_NAME="EthernetLink"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_status.sh
service_get() {
	local object="${1%.*}" lowlayer buf
	cmclient -v ifname GETV "$object.Name"
	if [ -n "$ifname" ]; then
		case "$1" in
		*.MACAddress)
			cmclient -v lowlayer GETV "$object.LowerLayers"
			case "$lowlayer" in
			*"ATM.Link"* | *"PTM.Link"* | *"Bridging.Bridge"* | *"X_ADB_MobileModem.Interface"*)
				help_get_base_stats "$1" "$ifname"
				return
				;;
			*)
				cmclient -v buf GETV "$lowlayer.MACAddress"
				;;
			esac
			;;
		*)
			help_get_base_stats "$1" "$ifname"
			return
			;;
		esac
	fi
	echo $buf
}
service_config() {
	local _status
	case "$obj" in
	Device.Ethernet.Link.*)
		if [ "$changedEnable" = "1" ] || [ "$user" = "InterfaceStack" -a "$setEnable" = "1" ]; then
			[ "$newX_ADB_Promisc" = "true" ] && ifconfig $newName promisc || ifconfig $newName -promisc
			help_get_status_from_lowerlayers _status "$obj"
			[ "$newStatus" != "$_status" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "$_status"
		fi
		if [ "$changedX_ADB_Promisc" = "1" ]; then
			[ "$newX_ADB_Promisc" = "true" ] && ifconfig $newName promisc || ifconfig $newName -promisc
		fi
		;;
	esac
}
case "$op" in
g)
	for arg; do # Arg list as separate words
		service_get "$obj.$arg"
	done
	;;
s)
	service_config
	;;
esac
exit 0
