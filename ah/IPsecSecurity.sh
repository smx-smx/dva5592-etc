#!/bin/sh
AH_NAME="IPsecSecurity"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_ipsec.sh
restart_required() {
	local IPsec_Enable
	cmclient -v IPsec_Enable GETV "Device.IPsec.Enable"
	[ "$IPsec_Enable" = "false" ] && return 1
	[ "$changedEnable" = "1" ] && return 0
	[ "$newEnable" = "false" ] && return 1
	help_is_changed "Side" "IdentifierType" "IdentifierValue" "Order" "PSK" || return 1
}
service_add() {
	local obj_num=$(cmclient GETO Device.IPsec.X_ADB_Security.+ | wc -l)
	cmclient SETE "${obj}.Order" "$obj_num"
}
service_delete() {
	help_dom_reorder "IPsec.X_ADB_Security" "del" "$newOrder" "$obj"
	[ "$newEnable" = "true" ] && ipsec_commit
}
service_config() {
	if [ $changedOrder -eq 1 ]; then
		echo "$AH_NAME: $obj changing Order [$oldOrder]->[$newOrder]"
		help_dom_reorder "IPsec.X_ADB_Security" "del" "$oldOrder" "$obj"
		help_dom_reorder "IPsec.X_ADB_Security" "add" "$newOrder" "$obj"
	fi
	if restart_required; then ipsec_commit; fi
}
case "$op" in
a)
	service_add
	;;
d)
	service_delete
	;;
s)
	service_config
	;;
esac
exit 0
