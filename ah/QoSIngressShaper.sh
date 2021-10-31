#!/bin/sh
AH_NAME="QoSIngressShaper"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/target.sh
service_delete() {
	cmclient -v iface_val GETV "$newInterface.Name"
	[ -n "$iface_val" ] && ethsw_set_ingress_shaper "$(echo "$iface_val" | tr -d [a-z])" 0 128
}
service_config() {
	help_is_changed Interface ShapingBurstSize ShapingRate ||
		[ "$setEnable" = "1" ] || exit 0
	if [ "$newEnable" = "false" ]; then
		if [ "$changedEnable" -eq 1 ]; then
			cmclient -v iface_val GETV "$newInterface.Name"
			[ -n "$iface_val" ] && ethsw_set_ingress_shaper "$(echo "$iface_val" | tr -d [a-z])" 0 128
			cmclient SETE "$obj.Status" "Disabled"
		fi
		return
	fi
	cmclient -v iface_val GETV "$newInterface.Name"
	[ -z "$iface_val" ] && return
	if [ -n "$newShapingBurstSize" ]; then
		ethsw_set_ingress_shaper "$(echo "$iface_val" | tr -d [a-z])" "$((newShapingRate / 1000))" "$((newShapingBurstSize * 8 / 1000))"
	else
		ethsw_set_ingress_shaper "$(echo "$iface_val" | tr -d [a-z])" "$((newShapingRate / 1000))" 0
	fi
	cmclient SETE "$obj.Status" "Enabled"
}
case "$op" in
s)
	service_config
	;;
d)
	service_delete
	;;
esac
exit 0
