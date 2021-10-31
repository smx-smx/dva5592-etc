#!/bin/sh
service_get() {
local obj181="$1" param98="$2" value98=
case "$param98" in
"InternalPort")
cmclient -v value98 GETV $obj181.InternalPort
[ ${value98:-0} -eq 0 ] && cmclient -v value98 GETV $obj181.ExternalPort
[ $value98 -eq 0 ] && value98=99999
;;
esac
echo "$value98"
}
service_set() {
local obj98="$1" obj181="$2" val
if [ "$setInternalPort" = "1" ]; then
cmclient -v val GETV "$obj181.ExternalPort"
[ "$newInternalPort" = "$val" -o "$newInternalPort" = "99999" ] && newInternalPort=0
cmclient -u "tr098" SET "$obj181.InternalPort $newInternalPort"
fi
}
cmclient -v obj181 GETV "$obj.X_ADB_TR181Name"
case "$op" in
g)
for arg; do
[ ${#obj181} -ne 0 ] && \
service_get "$obj181" "$arg" || \
echo ""
done
;;
s)
[ ${#obj181} -ne 0 ] && service_set "$obj" "$obj181"
;;
esac
exit 0
