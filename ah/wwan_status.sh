#!/bin/sh
AH_NAME=MobModemStatus
[ "$changedStatus" = "1" ] || exit 0
cmclient -v mmodl GETV $obj.Modem.ActiveModel
cmclient -v mtype GETV $mmodl.ModemInterfaceType
[ -z "$mtype" ] && exit 0
case $mtype in
"SERIAL")
	iface="Device.PPP.Interface"
	;;
"QMI" | "HUAWEI_NCM" | "CDC_ECM" | "CDC_MBIM")
	iface="Device.Ethernet.Link"
	cmclient -v ifname GETV "$iface.[Enable=true].[LowerLayers=$obj].Name"
	[ "$newStatus" = "Up" ] && op="up" || op="down"
	;;
*)
	exit 0
	;;
esac
cmclient -a -u InterfaceStack SET "$iface.[Enable=true].[LowerLayers=$obj].Enable" true
[ "$newStatus" = "Up" ] && cmclient -a -u InterfaceStack SET "$iface.[LowerLayers=$obj].X_ADB_ActiveLowerLayer" "$obj"
[ -n "$ifname" ] && ip link set $ifname $op
exit 0
