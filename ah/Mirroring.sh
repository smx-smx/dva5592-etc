#!/bin/sh
AH_NAME="Mirroring"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/target.sh
service_delete() {
local indev outdev
cmclient -v indev GETV "$oldMonitorInterface".Name
cmclient -v outdev GETV "$oldMirrorInterface".Name
case "$oldMonitorInterface" in
Device.[AP]TM.Link.*)
xtm_mirror_disable "$indev" "$outdev"
;;
Device.Ethernet.Interface.*)
if [ -x /bin/mirror -a -f /tmp/mirror_"$obj" ]; then
read mpid < /tmp/mirror_"$obj"
kill $mpid
rm /tmp/mirror_"$obj"
fi
;;
esac
}
service_config() {
local indev outdev if_status tmp dqry=""
[ "$changedEnable" = "0" -a "$newEnable" = "false" ] && return
if [ "$newEnable" = "true" ]; then
[ "$newDirection" != "Bidirectional" ] && dqry=".[Direction<$newDirection,Bidirectional]"
cmclient -v tmp GETO "Device.X_ADB_Mirroring.Mirror.*.[MonitorInterface=$newMonitorInterface].[Enable=true]$dqry"
for tmp in $tmp; do
[ "$tmp" = "$obj" ] || exit 1
done
case "$newMonitorInterface" in
Device.[AP]TM.Link.*)
;;
Device.Ethernet.Interface.*)
[ -x /bin/mirror ] || return
;;
*)
return
;;
esac
cmclient -v if_status GETV "$newMonitorInterface".Status
[ "$if_status" = "Up" ] || return
fi
[ "$setEnable" = "0" -o "$changedEnable" = "1" ] && service_delete
[ "$newEnable" = "false" ] && return
cmclient -v indev GETV "$newMonitorInterface".Name
cmclient -v outdev GETV "$newMirrorInterface".Name
case "$newMonitorInterface" in
Device.[AP]TM.Link.*)
xtm_mirror_enable "$indev" "$outdev" "$newDirection"
;;
Device.Ethernet.Interface.*)
[ -x /bin/mirror ] || return
if [ -f /tmp/mirror_"$obj" ]; then
read mpid < /tmp/mirror_"$obj"
kill $mpid
rm /tmp/mirror_"$obj"
fi
case "$newDirection" in
Inbound)
mirror -i "$indev" -o "$outdev" -d "in" &
;;
Outbound)
mirror -i "$indev" -o "$outdev" -d "out" &
;;
Bidirectional)
mirror -i "$indev" -o "$outdev" -d "inout" &
;;
esac
echo "$!" > /tmp/mirror_"$obj"
;;
esac
}
case "$op" in
d)
service_delete
;;
s)
case "$obj" in
Device.X_ADB_Mirroring.Mirror.*)
service_config
;;
*)
[ "$changedStatus" = 1 ] && . /etc/ah/helper_lastChange.sh && help_lastChange_set "$obj"
cmclient -v obj GETO "Device.X_ADB_Mirroring.Mirror.*.[Enable=true].[MonitorInterface=$obj]"
for obj in $obj; do
cmclient SET 'Device.X_ADB_Mirroring.Mirror.*.Enable' 'true'
done
;;
esac
;;
esac
exit 0
