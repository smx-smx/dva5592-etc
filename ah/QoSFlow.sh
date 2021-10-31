#!/bin/sh
AH_NAME="QoSFlow"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_functions.sh
service_delete() {
help_iptables -t mangle -F "$obj"
help_iptables -t mangle -D Flows -j "$obj"
help_iptables -t mangle -D LocalFlows -j "$obj"
help_iptables -t mangle -X "$obj"
ebtables -t filter -D INPUT -j "$obj"
ebtables -t filter -X "$obj"
}
service_config() {
help_is_changed App DSCPMark EthernetPriorityMark ForwardingPolicy Policer TrafficClass || \
[ "$setEnable" = "1" ] || exit 0
service_delete
help_iptables commit noerr
if [ "$newEnable" = "false" ]; then
[ "$changedEnable" = "1" ] && cmclient SETE "$obj.Status" "Disabled"
return
fi
cmclient SETE "$obj.Status" "Enabled"
help_iptables -t mangle -N "$obj"
help_iptables -t mangle -A LocalFlows -j "$obj"
help_iptables -t mangle -A Flows -j "$obj"
cmclient -v helper_urn GETV "$newApp".ProtocolIdentifier
if [ "$helper_urn" = "urn:dslforum-org:ftp" ]; then
helper="ftp"
elif [ "$helper_urn" = "urn:dslforum-org:tftp" ]; then
helper="tftp"
elif [ "$helper_urn" = "urn:dslforum-org:pptp" ]; then
helper="pptp"
elif [ "$helper_urn" = "urn:dslforum-org:ipsec" ]; then
helper="ipsec"
elif [ "$helper_urn" = "urn:dslforum-org:sip" ]; then
helper="sip"
elif [ "$helper_urn" = "urn:dslforum-org:h323" ]; then
helper="h323"
fi
help_iptables -t mangle -A "$obj" -m helper ! --helper "$helper" -j RETURN
help_iptables -t mangle -A "$obj" -m helper --helper "$helper" -j MARK --set-mark $((newTrafficClass*16777216))/0xFF000000
help_iptables -t mangle -A "$obj" -m helper --helper "$helper" -j MARK --set-mark $newForwardingPolicy/0x000000FF
[ -n "$newPolicer" -a "$newPolicer" != "-1" ] && \
help_iptables -t mangle -A "$obj" -j "$newPolicer"
ebt_match=0
if [ -n "$newDSCPMark" ] && [ "$newDSCPMark" != "-1" ]; then
if [ "$newDSCPMark" = "-2" ]; then
ebt_match=1
ebt_dscp_rule1="ebtables -t filter -A $obj -p 0x8100 --vlan-prio 0 -j mark --set-mark 0x00000000"
ebt_dscp_rule2="ebtables -t filter -A $obj -p 0x8100 --vlan-prio 1 -j mark --set-mark 0x00010000"
ebt_dscp_rule3="ebtables -t filter -A $obj -p 0x8100 --vlan-prio 2 -j mark --set-mark 0x00020000"
ebt_dscp_rule4="ebtables -t filter -A $obj -p 0x8100 --vlan-prio 3 -j mark --set-mark 0x00030000"
ebt_dscp_rule5="ebtables -t filter -A $obj -p 0x8100 --vlan-prio 4 -j mark --set-mark 0x00040000"
ebt_dscp_rule6="ebtables -t filter -A $obj -p 0x8100 --vlan-prio 5 -j mark --set-mark 0x00050000"
ebt_dscp_rule7="ebtables -t filter -A $obj -p 0x8100 --vlan-prio 6 -j mark --set-mark 0x00060000"
ebt_dscp_rule8="ebtables -t filter -A $obj -p 0x8100 --vlan-prio 7 -j mark --set-mark 0x00070000"
dscp_rule1="help_iptables -t mangle -A $obj -m mark --mark 0x00000000/0x00070000 -j DSCP --set-dscp 0"
dscp_rule2="help_iptables -t mangle -A $obj -m mark --mark 0x00010000/0x00070000 -j DSCP --set-dscp 0"
dscp_rule3="help_iptables -t mangle -A $obj -m mark --mark 0x00020000/0x00070000 -j DSCP --set-dscp 0"
dscp_rule4="help_iptables -t mangle -A $obj -m mark --mark 0x00030000/0x00070000 -j DSCP --set-dscp 0x08"
dscp_rule5="help_iptables -t mangle -A $obj -m mark --mark 0x00040000/0x00070000 -j DSCP --set-dscp 0x10"
dscp_rule6="help_iptables -t mangle -A $obj -m mark --mark 0x00050000/0x00070000 -j DSCP --set-dscp 0x18"
dscp_rule7="help_iptables -t mangle -A $obj -m mark --mark 0x00060000/0x00070000 -j DSCP --set-dscp 0x28"
dscp_rule8="help_iptables -t mangle -A $obj -m mark --mark 0x00070000/0x00070000 -j DSCP --set-dscp 0x38"
else
dscp_rule="help_iptables -t mangle -A $obj -j DSCP --set-dscp $newDSCPMark"
fi
fi
if [ -n "$newEthernetPriorityMark" ] && [ "$newEthernetPriorityMark" != "-1" ]; then
if [ "$newEthernetPriorityMark" = "-2" ]; then
vlan_rule1="help_iptables -t mangle -A $obj -m dscp --dscp 0x0 -j MARK --or-mark 0x00600000"
vlan_rule2="help_iptables -t mangle -A $obj -m dscp --dscp 0x0e -j MARK --or-mark 0x00600000"
vlan_rule3="help_iptables -t mangle -A $obj -m dscp --dscp 0x0c -j MARK --or-mark 0x00600000"
vlan_rule4="help_iptables -t mangle -A $obj -m dscp --dscp 0x0a -j MARK --or-mark 0x00600000"
vlan_rule5="help_iptables -t mangle -A $obj -m dscp --dscp 0x08 -j MARK --or-mark 0x00600000"
vlan_rule6="help_iptables -t mangle -A $obj -m dscp --dscp 0x16 -j MARK --or-mark 0x00800000"
vlan_rule7="help_iptables -t mangle -A $obj -m dscp --dscp 0x14 -j MARK --or-mark 0x00800000"
vlan_rule8="help_iptables -t mangle -A $obj -m dscp --dscp 0x12 -j MARK --or-mark 0x00800000"
vlan_rule9="help_iptables -t mangle -A $obj -m dscp --dscp 0x10 -j MARK --or-mark 0x00800000"
vlan_rule10="help_iptables -t mangle -A $obj -m dscp --dscp 0x1e -j MARK --or-mark 0x00A00000"
vlan_rule11="help_iptables -t mangle -A $obj -m dscp --dscp 0x1c -j MARK --or-mark 0x00A00000"
vlan_rule12="help_iptables -t mangle -A $obj -m dscp --dscp 0x1a -j MARK --or-mark 0x00A00000"
vlan_rule13="help_iptables -t mangle -A $obj -m dscp --dscp 0x18 -j MARK --or-mark 0x00A00000"
vlan_rule14="help_iptables -t mangle -A $obj -m dscp --dscp 0x26 -j MARK --or-mark 0x00C00000"
vlan_rule15="help_iptables -t mangle -A $obj -m dscp --dscp 0x24 -j MARK --or-mark 0x00C00000"
vlan_rule16="help_iptables -t mangle -A $obj -m dscp --dscp 0x22 -j MARK --or-mark 0x00C00000"
vlan_rule17="help_iptables -t mangle -A $obj -m dscp --dscp 0x20 -j MARK --or-mark 0x00C00000"
vlan_rule18="help_iptables -t mangle -A $obj -m dscp --dscp 0x2e -j MARK --or-mark 0x00C00000"
vlan_rule19="help_iptables -t mangle -A $obj -m dscp --dscp 0x28 -j MARK --or-mark 0x00C00000"
vlan_rule20="help_iptables -t mangle -A $obj -m dscp --dscp 0x30 -j MARK --or-mark 0x00E00000"
vlan_rule21="help_iptables -t mangle -A $obj -m dscp --dscp 0x38 -j MARK --or-mark 0x00E00000"
else
vlan_rule="help_iptables -t mangle -A $obj -j MARK --set-mark $((newEthernetPriorityMark * 2097152))/0x00E00000"
fi
fi
if [ $ebt_match -eq 1 ]; then
ebtables -t filter -N $obj
ebtables -t filter -A INPUT -j $obj
$ebt_dscp_rule1; $ebt_dscp_rule2; $ebt_dscp_rule3; $ebt_dscp_rule4
$ebt_dscp_rule5; $ebt_dscp_rule6; $ebt_dscp_rule7; $ebt_dscp_rule8
fi
if [ -n "$vlan_rule" ]; then
$vlan_rule
elif [ -n "$vlan_rule1" ]; then
$vlan_rule1; $vlan_rule2; $vlan_rule3; $vlan_rule4
$vlan_rule5; $vlan_rule6; $vlan_rule7; $vlan_rule8
$vlan_rule9; $vlan_rule10; $vlan_rule11; $vlan_rule12
$vlan_rule13; $vlan_rule14; $vlan_rule15; $vlan_rule16
$vlan_rule17; $vlan_rule18; $vlan_rule19; $vlan_rule20; $vlan_rule21
fi
if [ -n "$dscp_rule" ]; then
$dscp_rule
elif [ -n "$dscp_rule1" ]; then
$dscp_rule1; $dscp_rule2; $dscp_rule3; $dscp_rule4
$dscp_rule5; $dscp_rule6; $dscp_rule7; $dscp_rule8
fi
help_iptables -t mangle -A $obj -j ACCEPT
}
case "$op" in
d)
service_delete
;;
s)
service_config
;;
esac
exit 0
