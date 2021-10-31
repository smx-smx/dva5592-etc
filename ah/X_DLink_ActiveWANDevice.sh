#!/bin/sh
AH_NAME="X_DLink_ActiveWANDevice.sh"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
active_wan_device_object=""
cmclient -v active_wan_device_object GETV "InternetGatewayDevice.Layer3Forwarding.DefaultConnectionService"
service_config() {
[ "$changedEnable" = "1" ] && cmclient SET "$active_wan_device_object.Enable $newEnable"
[ "$changedPassword" = "1" ] && cmclient SET "$active_wan_device_object.Password $newPassword"
[ "$changedUsername" = "1" ] && cmclient SET "$active_wan_device_object.Username $newUsername"
}
service_get() {
local value="" obj="$1" arg="$2" query="" wan_access_type="" atm_encapsulation="" link_type=""
if [ "$arg" = "DataConnectionInterface" ]; then
cmclient SETE "$obj.DataConnectionInterface $active_wan_device_object" > /dev/null
value=$active_wan_device_object
elif [ "$arg" = "ATMEncapsulation" ]; then
query=${active_wan_device_object%.WANPPPConnection*}
cmclient -v atm_encapsulation GETV "$query.**.ATMEncapsulation"
cmclient SETE "$obj.ATMEncapsulation $atm_encapsulation" > /dev/null
value=$atm_encapsulation
elif [ "$arg" = "LinkType" ]; then
query=${active_wan_device_object%.WANPPPConnection*}
cmclient -v link_type GETV "$query.**.LinkType"
cmclient SETE "$obj.LinkType $link_type" > /dev/null
value=$link_type
elif [ "$arg" = "WANAccessType" ]; then
query=${active_wan_device_object%.WANConnectionDevice*}
cmclient -v wan_access_type GETV "$query.WANCommonInterfaceConfig.WANAccessType"
cmclient SETE "$obj.$arg $wan_access_type" > /dev/null
value=$wan_access_type
else
cmclient -v value GETV "$active_wan_device_object.$arg"
cmclient SETE "$obj.$arg $value" > /dev/null
fi
echo "$value"
}
case "$op" in
s)
service_config
;;
g)
for arg; do  # arg list as separate words
service_get "$obj" "$arg"
done
;;
esac
exit 0
