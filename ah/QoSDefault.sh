#!/bin/sh
service_config() {
	while iptables -t mangle -D PREROUTING 11; do
		:
	done
	if [ -n "$newDefaultDSCPMark" ] && [ "$newDefaultDSCPMark" != "-1" ]; then
		if [ "$newDefaultDSCPMark" = "-2" ]; then
			ebt_dscp_rule1="ebtables -t filter -A INPUT -p 0x8100 --vlan-prio 0 -j mark --set-mark 0x00000000"
			ebt_dscp_rule2="ebtables -t filter -A INPUT -p 0x8100 --vlan-prio 1 -j mark --set-mark 0x00010000"
			ebt_dscp_rule3="ebtables -t filter -A INPUT -p 0x8100 --vlan-prio 2 -j mark --set-mark 0x00020000"
			ebt_dscp_rule4="ebtables -t filter -A INPUT -p 0x8100 --vlan-prio 3 -j mark --set-mark 0x00030000"
			ebt_dscp_rule5="ebtables -t filter -A INPUT -p 0x8100 --vlan-prio 4 -j mark --set-mark 0x00040000"
			ebt_dscp_rule6="ebtables -t filter -A INPUT -p 0x8100 --vlan-prio 5 -j mark --set-mark 0x00050000"
			ebt_dscp_rule7="ebtables -t filter -A INPUT -p 0x8100 --vlan-prio 6 -j mark --set-mark 0x00060000"
			ebt_dscp_rule8="ebtables -t filter -A INPUT -p 0x8100 --vlan-prio 7 -j mark --set-mark 0x00070000"
			dscp_rule1="iptables -t mangle -A PREROUTING -m mark --mark 0x00000000/0x00070000 -j DSCP --set-dscp 0"
			dscp_rule2="iptables -t mangle -A PREROUTING -m mark --mark 0x00010000/0x00070000 -j DSCP --set-dscp 0"
			dscp_rule3="iptables -t mangle -A PREROUTING -m mark --mark 0x00020000/0x00070000 -j DSCP --set-dscp 0"
			dscp_rule4="iptables -t mangle -A PREROUTING -m mark --mark 0x00030000/0x00070000 -j DSCP --set-dscp 0x08"
			dscp_rule5="iptables -t mangle -A PREROUTING -m mark --mark 0x00040000/0x00070000 -j DSCP --set-dscp 0x10"
			dscp_rule6="iptables -t mangle -A PREROUTING -m mark --mark 0x00050000/0x00070000 -j DSCP --set-dscp 0x18"
			dscp_rule7="iptables -t mangle -A PREROUTING -m mark --mark 0x00060000/0x00070000 -j DSCP --set-dscp 0x28"
			dscp_rule8="iptables -t mangle -A PREROUTING -m mark --mark 0x00070000/0x00070000 -j DSCP --set-dscp 0x38"
		else
			dscp_rule="iptables -t mangle -A PREROUTING -j DSCP --set-dscp $newDefaultDSCPMark"
		fi
	fi
	if [ -n "$newDefaultEthernetPriorityMark" ] && [ "$newDefaultEthernetPriorityMark" != "-1" ]; then
		if [ "$newDefaultEthernetPriorityMark" = "-2" ]; then
			vlan_rule1="iptables -t mangle -A PREROUTING -m dscp --dscp 0x0 -j MARK --or-mark 0x00600000"
			vlan_rule2="iptables -t mangle -A PREROUTING -m dscp --dscp 0x0e -j MARK --or-mark 0x00600000"
			vlan_rule3="iptables -t mangle -A PREROUTING -m dscp --dscp 0x0c -j MARK --or-mark 0x00600000"
			vlan_rule4="iptables -t mangle -A PREROUTING -m dscp --dscp 0x0a -j MARK --or-mark 0x00600000"
			vlan_rule5="iptables -t mangle -A PREROUTING -m dscp --dscp 0x08 -j MARK --or-mark 0x00600000"
			vlan_rule6="iptables -t mangle -A PREROUTING -m dscp --dscp 0x16 -j MARK --or-mark 0x00800000"
			vlan_rule7="iptables -t mangle -A PREROUTING -m dscp --dscp 0x14 -j MARK --or-mark 0x00800000"
			vlan_rule8="iptables -t mangle -A PREROUTING -m dscp --dscp 0x12 -j MARK --or-mark 0x00800000"
			vlan_rule9="iptables -t mangle -A PREROUTING -m dscp --dscp 0x10 -j MARK --or-mark 0x00800000"
			vlan_rule10="iptables -t mangle -A PREROUTING -m dscp --dscp 0x1e -j MARK --or-mark 0x00A00000"
			vlan_rule11="iptables -t mangle -A PREROUTING -m dscp --dscp 0x1c -j MARK --or-mark 0x00A00000"
			vlan_rule12="iptables -t mangle -A PREROUTING -m dscp --dscp 0x1a -j MARK --or-mark 0x00A00000"
			vlan_rule13="iptables -t mangle -A PREROUTING -m dscp --dscp 0x18 -j MARK --or-mark 0x00A00000"
			vlan_rule14="iptables -t mangle -A PREROUTING -m dscp --dscp 0x26 -j MARK --or-mark 0x00C00000"
			vlan_rule15="iptables -t mangle -A PREROUTING -m dscp --dscp 0x24 -j MARK --or-mark 0x00C00000"
			vlan_rule16="iptables -t mangle -A PREROUTING -m dscp --dscp 0x22 -j MARK --or-mark 0x00C00000"
			vlan_rule17="iptables -t mangle -A PREROUTING -m dscp --dscp 0x20 -j MARK --or-mark 0x00C00000"
			vlan_rule18="iptables -t mangle -A PREROUTING -m dscp --dscp 0x2e -j MARK --or-mark 0x00C00000"
			vlan_rule19="iptables -t mangle -A PREROUTING -m dscp --dscp 0x28 -j MARK --or-mark 0x00C00000"
			vlan_rule20="iptables -t mangle -A PREROUTING -m dscp --dscp 0x30 -j MARK --or-mark 0x00E00000"
			vlan_rule21="iptables -t mangle -A PREROUTING -m dscp --dscp 0x38 -j MARK --or-mark 0x00E00000"
		else
			vlan_rule="iptables -t mangle -A PREROUTING -j MARK --set-mark $((newDefaultEthernetPriorityMark * 2097152))/0x00E00000"
		fi
	fi
	if [ -n "$newDefaultPolicer" ]; then
		iptables -t mangle -A PREROUTING -j "$newDefaultPolicer"
	fi
	if [ -n "$newDefaultTrafficClass" ] && [ "$newDefaultTrafficClass" != "_" ]; then
		iptables -t mangle -A PREROUTING -j MARK --set-mark $((newDefaultTrafficClass * 16777216))/0xFF000000
	fi
	if [ -n "$newDefaultForwardingPolicy" ] && [ "$newDefaultForwardingPolicy" != "_" ]; then
		iptables -t mangle -A PREROUTING -j MARK --set-mark $newDefaultForwardingPolicy/0x000000FF
	fi
	if [ -n "$dscp_rule" ]; then
		$dscp_rule
	elif [ -n "$dscp_rule1" ]; then
		$dscp_rule1
		$dscp_rule2
		$dscp_rule3
		$dscp_rule4
		$dscp_rule5
		$dscp_rule6
		$dscp_rule7
		$dscp_rule8
	fi
	if [ -n "$vlan_rule" ]; then
		$vlan_rule
	elif [ -n "$vlan_rule1" ]; then
		$vlan_rule1
		$vlan_rule2
		$vlan_rule3
		$vlan_rule4
		$vlan_rule5
		$vlan_rule6
		$vlan_rule7
		$vlan_rule8
		$vlan_rule9
		$vlan_rule10
		$vlan_rule11
		$vlan_rule12
		$vlan_rule13
		$vlan_rule14
		$vlan_rule15
		$vlan_rule16
		$vlan_rule17
		$vlan_rule18
		$vlan_rule19
		$vlan_rule20
		$vlan_rule21
	fi
	if [ -n "$ebt_dscp_rule1" ]; then
		$ebt_dscp_rule1
		$ebt_dscp_rule2
		$ebt_dscp_rule3
		$ebt_dscp_rule4
		$ebt_dscp_rule5
		$ebt_dscp_rule6
		$ebt_dscp_rule7
		$ebt_dscp_rule8
	elif [ -n "$ebt_dscp_rule" ]; then
		$ebt_dscp_rule
	fi
}
case "$op" in
s)
	service_config
	;;
esac
exit 0
