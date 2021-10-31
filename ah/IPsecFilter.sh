#!/bin/sh
AH_NAME="IPsecFilter"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_ipsec.sh
restart_required() {
local IPsec_Enable
cmclient -v IPsec_Enable GETV "Device.IPsec.Enable"
[ "$IPsec_Enable" = "false" ] && return 1
case "$obj" in
*".X_ADB_RoadWarrior")
local DadFilter=${obj%.X_ADB_RoadWarrior} DadFilter_Enable
filter_obj="$DadFilter"
cmclient -v DadFilter_Enable GETV "${DadFilter}.Enable"
[ "$DadFilter_Enable" = "false" ] && return 1
help_is_changed "Enable" "Type" "DNSServers" "Address" "SubnetMask" || return 1
;;
*)
if [ "$changedEnable" = "1" ]; then
[ "$newEnable" = "false" ] && cmclient SETE $obj.Status Disabled
return 0
fi
[ "$newEnable" = "false" ] && return 1
[ $newStatus = "Enabled" ] && \
help_is_changed "DestIP" "DestMask" "SourceIP" "SourceMask" \
"ProcessingChoice" "Profile" "Order" || return 1
;;
esac
}
service_add() {
case "$obj" in
*"X_ADB_RoadWarrior")
exit 0
;;
"Device.IPsec.Filter"*)
local ftobj filter_number count=0
cmclient -v filter_number GETO Device.IPsec.Filter.+
for filter_number in $filter_number; do count=$((count+1)); done
filter_number=$((count/2))
cmclient SETE "${obj}.Order" "$filter_number"
help_enforcetunnel "$obj"
;;
esac
}
service_delete() {
case "$obj" in
*"X_ADB_RoadWarrior")
exit 0
;;
"Device.IPsec.Filter"*)
help_dom_reorder "IPsec.Filter" "del" "$newOrder" "$obj"
cmclient DEL "Device.IPsec.Tunnel.[Filters=$obj]"
if [ "$newEnable" = "true" ]; then
cmclient SETE $obj.Enable false
ipsec_commit
fi
;;
esac
}
service_config() {
filter_obj="$obj"
if [ "$changedOrder" = "1" ]; then
echo "$AH_NAME: $obj changing Order [$oldOrder]->[$newOrder]"
help_dom_reorder "IPsec.Filter" "del" "$oldOrder" "$obj"
help_dom_reorder "IPsec.Filter" "add" "$newOrder" "$obj"
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
