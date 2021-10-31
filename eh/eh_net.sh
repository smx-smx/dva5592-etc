#!/bin/sh
#nl:add,net,eth*
#sync:max=5
. /etc/ah/target.sh
EH_NAME="eh_net"
. /etc/ah/helper_serialize.sh && help_serialize $EH_NAME
eth_enable() {
local ifname="$1"
sleep 1
printf '[\033[1;34m%s\033[m] %s\n' "$ifname" "down"
ethsw_power "$ifname" "down" 
while [ ! -e /tmp/cm_ready ]; do
sleep 1
done
cmclient -v ethObj GETO "Device.Ethernet.Interface.[Name=$ifname].[Enable=true]"
[ -n "$ethObj" ] && cmclient -u "boot" SET "$ethObj.Enable" "true"
eth_set_egress_tm $ifname
touch /tmp/${ifname}_ready
}
case "$OBJ" in
"eth"*"."*)
;;
*"_br"*)
;;
"eth"*)
eth_enable "$OBJ"
;;
esac
