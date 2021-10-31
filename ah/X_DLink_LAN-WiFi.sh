#!/bin/sh
AH_NAME="X_DLink_LAN-WiFi.sh"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
service_get() {
local tr098_obj="$1" tr098_arg="$2" value="" tr181_associated_device="" tr181_arg="" position=0 vendor="X_DLINK_"
position=${#vendor}
tr181_arg=${tr098_arg:$position}
cmclient -v tr181_associated_device GETV "$tr098_obj.X_ADB_TR181Name"
cmclient -v value GETV "$tr181_associated_device.$tr181_arg"
echo "$value"
}
case "$op" in
g)
for arg; do  # arg list as separate words
service_get "$obj" "$arg"
done
;;
esac
exit 0