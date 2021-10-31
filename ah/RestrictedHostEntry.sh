#!/bin/sh
AH_NAME="RestrictedHostEntry"
[ "$user" = "${AH_NAME}" ] && exit 0
. /etc/ah/helper_restricted_host.sh
help_serialize RestrictedHostRules > /dev/null
cmclient -v ro_enabled GETV X_ADB_ParentalControl.Enable
[ "$ro_enabled" = "false" ] && exit 0
service_get() {
ret=0
cmclient -v mac GETV "$obj.MACAddress"
if [ -n "$mac" ]; then
cmclient -v host GETO Device.Hosts.Host.[PhysAddress="$mac"]
if [ -n "$host" ]; then
case "$1" in
"SubnetID")
iface="`cmclient GETV "$host".Layer3Interface`"
eth_link="`cmclient GETV "$iface".LowerLayers`"
br="`cmclient GETV "$eth_link".LowerLayers`"
ret="${br##*Bridge.}"
ret="${ret%%.*}"
;;
"HostID")
ret="${host##*.}"
;;
esac
fi
fi
echo "$ret"
}
if [ "$op" = "d" ]; then
[ "$oldEnable" = "false" ] && exit 0
create_rules DEL "$oldTypeOfRestriction" "$oldMACAddress" "$oldEnabled" "$oldBlocked" "1"
elif [ "$op" = "s" ]; then
if [ "$changedProfile" -eq 1 ]; then
[ -z "$newProfile" -o -z "`cmclient GETO Device.X_ADB_ParentalControl.RestrictedHosts.TimeOfDayProfile.$newProfile`" ] && exit 1
fi
if [ "$changedTypeOfRestriction" -eq 1 -a "$newTypeOfRestriction" != "TIMEOFDAY" ]; then
cmclient -u "${AH_NAME}" SET "$obj.Profile" "0" > /dev/null
cmclient -u "${AH_NAME}" SET "$obj.Blocked" "false" > /dev/null
fi
if [ "$changedMACAddress" -eq 1 ]; then
if [ -n "$newMACAddress" ]; then
new_mac="`echo "$newMACAddress" | tr [A-F] [a-f]`"
cmclient -u "${AH_NAME}" SET "$obj.MACAddress" "$new_mac" > /dev/null
fi
else
new_mac="$newMACAddress"
fi
if [ ! -f /sbin/cbpc-dnsp ]; then
[ "$changedEnable" = "0" ] && [ "$newEnable" = "false" ] && exit 0
create_rules DEL "$oldTypeOfRestriction" "$oldMACAddress" "$oldEnable" "$oldBlocked" "$changedBlocked"
create_rules ADD "$newTypeOfRestriction" "$new_mac" "$newEnable" "$newBlocked" "$changedBlocked"
else
if [ "$changedEnable" = "1" -o "$changedBlocked" = "1" ]; then
create_rules ADD "$newTypeOfRestriction" "$new_mac" "$newEnable" "$newBlocked" "$changedBlocked"
fi
fi
elif [ "$op" = "g" ]; then
for arg # Arg list as separate words
do
service_get "$arg"
done
fi
