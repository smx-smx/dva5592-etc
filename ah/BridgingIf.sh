#!/bin/sh
AH_NAME="BridgeIf"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$user" = "InterfaceMonitor" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_lastChange.sh
. /etc/ah/target.sh
. /etc/ah/helper_stats.sh
service_get() {
local obj="$1" arg="$2" ifname br_name fake_port pobj untag vlan pvid
case "$arg" in
"Status" )
help_lowlayer_ifname_get ifname "${obj%.Stats*}"
eth_get_link_status "$ifname" ;;
LastChange)
help_lastChange_get "$obj"
;;
* )
help_lowlayer_ifname_get ifname "${obj%.Stats*}"
cmclient -v fake_port GETV "${obj%Stats*}X_ADB_FakePort"
if [ "$fake_port" = "true" ]; then
pobj=${obj%.Stats*}
cmclient -v untag GETV "${pobj%.Port*}.VLANPort.[Port=$pobj].Untagged"
if [ "$untag" = "false" ]; then
cmclient -v vlan GETV "${pobj%.Port*}.VLANPort.[Port=$pobj].VLAN"
cmclient -v pvid GETV $vlan.VLANID
[ -n "$pvid" ] && ifname="$ifname"."$pvid"
fi
cmclient -v br_name GETV "${obj%.*.Stats*}".[ManagementPort=true].Name
[ -n "$br_name" ] && ifname="$ifname"_"$br_name"
fi
help_get_base_stats_core "$obj.$arg" "$ifname" currentVal
eval "parVal=\$new$2"
if [ ${parVal:=0} -le $currentVal ]; then
echo $((currentVal-parVal))
else
echo $(((1<<32) - (parVal - currentVal)))
fi
;;
esac
}
service_config() {
case "$obj" in
Device.Bridging.Bridge.*.Port.*.Stats)
if [ "$setX_ADB_Reset" = "1" ]; then
help_reset_stats $obj
fi
;;
*)
[ "$changedStatus" = 1 ] && help_lastChange_set "$obj"
;;
esac
}
case "$op" in
g)
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
;;
s)
service_config
;;
esac
exit 0
