#!/bin/sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/IPv6_helper_firewall.sh
find_chains() {
	[ "$1" != tmp ] && local tmp
	[ "$1" != ret ] && local ret
	tmp=${2:-"%(Device.Firewall.[Config=Advanced].AdvancedLevel)"}
	cmclient -v tmp GETV "$tmp.Chain"
	ret=$tmp
	while [ -n "$tmp" ]; do
		for tmp in $tmp; do
			cmclient -v tmp GETV "$tmp.Rule.[Target=TargetChain].TargetChain"
			case " $ret " in
			*" $tmp "*)
				break 2
				;;
			*)
				ret="$ret $tmp"
				;;
			esac
		done
	done
	eval $1=\$ret
}
[ "$user" = "Firewall" ] && exit 0
if [ "${user%%_*}" = "init" ]; then
	user=${user#init_}
	init=1
fi
if [ "$init" != "1" ] && [ $# -ne 1 -o "$1" != "init" ]; then
	while [ -d /tmp/init_iptables ]; do sleep 0.1; done
	cmclient -v clt GETV Device.Time.CurrentLocalTime
	cmclient -u Firewall SET Device.Firewall.LastChange $clt
fi
case "${obj}" in Device.Firewall | Device.Firewall.*)
	[ "$setEnable" != "1" -o "$changedEnable" = "1" ] &&
		[ "$setDestInterface" != "1" -o "$changedDestInterface" = "1" ] &&
		[ "$setSourceInterface" != "1" -o "$changedSourceInterface" = "1" ] &&
		rm -f /tmp/cfg/cache/iptables /tmp/cfg/cache/ip6tables
	[ "$changedAdvancedLevel" = "1" ] &&
		rm -f /tmp/cfg/cache/iptables /tmp/cfg/cache/ip6tables
	[ "$setX_ADB_FlushCache" = "1" -a "$newX_ADB_FlushCache" = "true" ] &&
		rm -rft /tmp/cfg /tmp/cfg/cache/*
	;;
esac
linkLevels() {
	local chains
	if [ "$1" = "Advanced" ]; then
		levelID=${2##*.}
		help_iptables_all -N Firewall.L${levelID}
		help_iptables_all -N FirewallIn.L${levelID}
		help_iptables_all -N FirewallOut.L${levelID}
		find_chains chains $2
		for c in $chains; do
			chainID=${c##*.}
			help_iptables_all -N Firewall.C${chainID}
			help_iptables_all -N FirewallIn.C${chainID}
			help_iptables_all -N FirewallOut.C${chainID}
			cmclient -v r GETO $c.+.Rule
			for r in $r; do
				ruleID=${r##*.}
				help_iptables_all -N Firewall.C${chainID}.R${ruleID}
				help_iptables_all -N FirewallIn.C${chainID}.R${ruleID}
				help_iptables_all -N FirewallOut.C${chainID}.R${ruleID}
			done
		done
		for c in $chains; do
			cmclient SET -u "${3:+${3}_}${tmpiptablesprefix##*/}" $c.Rule.[Enable=true].Enable true
			cmclient SET -u "${3:+${3}_}${tmpiptablesprefix##*/}" $c.Rule.[Enable=false].Enable false
		done
		cmclient -v firstChain GETV ${2}.Chain
		chainID=${firstChain##*.}
		cmclient -v defaultPolicy GETV Device.Firewall.Level.$levelID.DefaultPolicy
		help_iptables_all -A Firewall.L"${levelID}" -j Firewall.C${chainID}
		help_iptables_all -A FirewallIn.L"${levelID}" -j FirewallIn.C${chainID}
		help_iptables_all -A FirewallOut.L"${levelID}" -j FirewallOut.C${chainID}
		help_iptables_all -A Firewall.L${levelID} -j $(echo "$defaultPolicy" | tr '[a-z]' '[A-Z]')
		help_iptables_all -A FirewallIn.L${levelID} -j $(echo "$defaultPolicy" | tr '[a-z]' '[A-Z]')
		help_iptables_all -A FirewallOut.L${levelID} -j $(echo "$defaultPolicy" | tr '[a-z]' '[A-Z]')
		help_iptables_all -A Firewall \
			-j Firewall.L${2##*.}
		help_iptables_all -A FirewallIn \
			-j FirewallIn.L${2##*.}
		help_iptables_all -A FirewallOut \
			-j FirewallOut.L${2##*.}
	else
		help_iptables_all -A Firewall -j Firewall.L"$1"
		help_iptables_all -A FirewallIn -j FirewallIn.L"$1"
	fi
}
refreshDefaultLevels() {
	help_iptables_all -F Firewall.LHigh
	help_iptables_all -F Firewall.LLow
	help_iptables_all -F FirewallIn.LHigh
	help_iptables_all -F FirewallIn.LLow
	help_iptables_all -F DNSIn
	help_iptables_all -F DNSOut
	help_iptables_all -F NTPOut
	help_iptables_all -F NTPIn
	local ipv6_enabled
	help_ip6tables -F Basic
	help_ip6tables -F BasicIn
	help_ip6tables -F BasicOut
	cmclient -v lan_ipv4s GETV Device.IP.Interface.[Enable=true].[X_ADB_Upstream=false].IPv4Address.[Enable=true].IPAddress
	cmclient -v lan_ipv6s GETV Device.IP.Interface.[Enable=true].[X_ADB_Upstream=false].IPv6Address.[Enable=true].IPAddress
	cmclient -v uipif GETO "Device.IP.Interface.[X_ADB_Upstream=true]"
	for uipif in $uipif; do
		help_lowlayer_ifname_get uif "$uipif"
		ports=$uif
		if [ ${uif%%[0-9]} = "br" ]; then
			cmclient -v brport GETO Bridging.Bridge.**.[Name=$uif]
			brif=${brport%%.Port.*}
			help_bridge_get_wan ports $brif
			is_enslaved=1
		elif isEnslaved "$uif"; then
			is_enslaved=1
		else
			is_enslaved=0
		fi
		ipv6_enabled=false
		[ "$ipv6_global" = "true" ] && cmclient -v ipv6_enabled GETV "$uipif.IPv6Enable"
		for cur_port in $ports; do
			if [ "$is_enslaved" -eq "1" ]; then
				inMatch="-m physdev --physdev-is-bridged --physdev-in $cur_port"
				outMatch="-m physdev --physdev-is-bridged --physdev-out $cur_port"
			else
				inMatch="-i $cur_port"
				outMatch="-o $cur_port"
			fi
			help_iptables_all -A Firewall.LHigh \
				${outMatch} \
				-p tcp -m multiport --dports 20,21,22,23,25,53,80,110,143,443 -j ACCEPT
			help_iptables_all -A Firewall.LHigh \
				${outMatch} \
				-p udp --dport 53 -j ACCEPT
			help_iptables_all -I DNSIn ${inMatch} -p tcp --dport 53 -j DROP
			help_iptables_all -I DNSIn ${inMatch} -p udp --dport 53 -j DROP
			help_iptables_all -I DNSIn ${inMatch} -p udp --sport 53 -j ACCEPT
			help_iptables_all -I DNSOut ${outMatch} -p tcp --dport 53 -j ACCEPT
			help_iptables_all -I DNSOut ${outMatch} -p udp --dport 53 -j ACCEPT
			help_iptables_all -I NTPOut ${outMatch} -p udp --dport 123 -j ACCEPT
			help_iptables_all -I NTPIn ${outMatch} -p udp --sport 123 -j ACCEPT
			help_iptables_all -I NTPIn ${inMatch} -p udp --dport 123 -m state --state NEW,INVALID,UNTRACKED -j DROP
			if [ "$ipv6_enabled" = "true" ]; then
				help_ip6tables -A Basic -s ff00::/8 -j DROP
				help_ip6tables -A BasicOut -s ff00::/8 -j DROP
				help_ip6tables -A Basic ${inMatch} -d ff01::/ff0f:: -j DROP # Interface-local scope
				help_ip6tables -A Basic ${outMatch} -d ff01::/ff0f:: -j DROP
				help_ip6tables -A Basic ${inMatch} -d ff02::/ff0f:: -j DROP # Link-local scope
				help_ip6tables -A Basic ${outMatch} -d ff02::/ff0f:: -j DROP
				help_ip6tables -A Basic ${inMatch} -d ff04::/ff0f:: -j DROP # Admin-local scope
				help_ip6tables -A Basic ${outMatch} -d ff04::/ff0f:: -j DROP
				help_ip6tables -A Basic ${inMatch} -d ff05::/ff0f:: -j DROP # Site-local scope
				help_ip6tables -A Basic ${outMatch} -d ff05::/ff0f:: -j DROP
				help_ip6tables -A Basic ${inMatch} -d ff08::/ff0f:: -j DROP # Organization-local scope
				help_ip6tables -A Basic ${outMatch} -d ff08::/ff0f:: -j DROP
				help_ip6tables -A Basic ${inMatch} -s fec0::/10 -j DROP # Site-local scope
				help_ip6tables -A Basic ${outMatch} -s fec0::/10 -j DROP
				help_ip6tables -A Basic ${inMatch} -d fec0::/10 -j DROP
				help_ip6tables -A Basic ${outMatch} -d fec0::/10 -j DROP
				help_ip6tables -A Basic ${inMatch} -s ::ffff:0:0/96 -j DROP # IPv4-Mapped Addresses
				help_ip6tables -A Basic ${outMatch} -s ::ffff:0:0/96 -j DROP
				help_ip6tables -A Basic ${inMatch} -d ::ffff:0:0/96 -j DROP
				help_ip6tables -A Basic ${outMatch} -d ::ffff:0:0/96 -j DROP
				help_ip6tables -A Basic ${inMatch} -s ::/96 -j DROP # IPv4-Compatible Addresses
				help_ip6tables -A Basic ${outMatch} -s ::/96 -j DROP
				help_ip6tables -A Basic ${inMatch} -d ::/96 -j DROP
				help_ip6tables -A Basic ${outMatch} -d ::/96 -j DROP
				help_ip6tables -A Basic ${inMatch} -s 2001:db8::/32 -j DROP # Documentation Prefix
				help_ip6tables -A Basic ${outMatch} -s 2001:db8::/32 -j DROP
				help_ip6tables -A Basic ${inMatch} -d 2001:db8::/32 -j DROP
				help_ip6tables -A Basic ${outMatch} -d 2001:db8::/32 -j DROP
				help_ip6tables -A Basic ${inMatch} -s 2001:10::/28 -j DROP # ORCHID
				help_ip6tables -A Basic ${outMatch} -s 2001:10::/28 -j DROP
				help_ip6tables -A Basic ${inMatch} -d 2001:10::/28 -j DROP
				help_ip6tables -A Basic ${outMatch} -d 2001:10::/28 -j DROP
				help_ip6tables -A Basic -m rt --rt-type 0 -j DROP
				help_ip6tables -A BasicOut -m rt --rt-type 0 -j DROP
				help_ip6tables -A Basic ${inMatch} -s fc00::/7 -j DROP
				help_ip6tables -A Basic ${outMatch} -s fc00::/7 -j DROP
				help_ip6tables -A Basic ${inMatch} -d fc00::/7 -j DROP
				help_ip6tables -A Basic ${outMatch} -d fc00::/7 -j DROP
				help_ip6tables -A BasicIn ${inMatch} -p udp --dport 53 -j DROP
				help_ip6tables -A BasicIn ${inMatch} -p tcp --dport 53 -j DROP # For zone transfer
				help_ip6tables -A BasicIn ${inMatch} -p udp --dport 547 -j DROP
			fi
			cmclient -v istrust GETV "$uipif.X_ADB_IsTrusted"
			if [ "$istrust" = "true" ]; then
				help_iptables -A Firewall.LHigh \
					${inMatch} \
					-j ACCEPT
				help_iptables -A Firewall.LLow \
					${inMatch} \
					-j ACCEPT
			else
				if [ "$is_enslaved" -eq "1" ]; then
					help_iptables_all -A Firewall.LLow \
						${inMatch} -m pkttype --pkt-type multicast -j ACCEPT
					help_iptables_all -A Firewall.LLow \
						${inMatch} -p udp --dport 68 --sport 67 -j ACCEPT
				fi
				help_iptables_all -A Firewall.LLow \
					${inMatch} \
					-m state ! --state ESTABLISHED,RELATED -j DROP
			fi
			for ip in $lan_ipv4s; do
				help_iptables -A FirewallIn.LHigh -i "$uif" -d "${ip}" -j DROP
				help_iptables -A FirewallIn.LLow -i "$uif" -d "${ip}" -j DROP
			done
			for ip in $lan_ipv6s; do
				help_ip6tables -A FirewallIn.LHigh -i "$uif" -d "${ip}" -j DROP
				help_ip6tables -A FirewallIn.LLow -i "$uif" -d "${ip}" -j DROP
			done
		done
	done
	local x y
	for x in In Out ""; do
		for y in 1 2 3 4 128 129 133 134 135 136 137 141 142 148 149; do
			help_ip6tables -A Basic$x -p ipv6-icmp --icmpv6-type $y -j ACCEPT
		done
		for y in 130 131 132 143 151 152 153; do
			help_ip6tables -A Basic$x -s fe80::/10 -p ipv6-icmp --icmpv6-type $y -j ACCEPT
		done
	done
	help_iptables_all -A Firewall.LHigh -m state --state ESTABLISHED,RELATED -j ACCEPT
	help_iptables_all -A Firewall.LHigh -j DROP
}
refreshPortMapping() {
	local tmp
	cmclient -v tmp GETV '%(Device.Firewall.[Config=Advanced].AdvancedLevel).PortMappingEnabled'
	[ "$tmp" != "false" ] && help_iptables -A ForwardAllow -j ForwardAllow_PortMapping
}
refreshAllowLocalServices() {
	local tmp
	cmclient -v tmp GETV '%(Device.Firewall.[Config=Advanced].AdvancedLevel).X_ADB_AllowLocalServices'
	if [ "$tmp" = "false" ]; then
		help_iptables_all -A ServicesIn -j ServicesIn_LocalACLServices
		help_iptables_all -A OutputAllow -j OutputAllow_LocalACLServices
	else
		help_iptables_all -A ServicesIn -j ServicesIn_LocalServices
		help_iptables_all -A OutputAllow -j OutputAllow_LocalServices
	fi
}
cmclient -v ipv6_global GETV "Device.IP.IPv6Enable"
if [ $# -eq 2 ] && [ "$1" = "ifchange" ]; then
	refreshDefaultLevels
	cmclient -v config GETV Device.Firewall.Config
	if [ "$config" = "Advanced" ]; then
		interface=$2
		case "$2" in
		Device.IP.Interface.*)
			cmclient -v ll GETV $2.LowerLayers
			case "$ll" in
			Device.PPP.Interface.*)
				interface=$ll
				;;
			esac
			;;
		esac
		find_chains c
		for c in $c; do
			cmclient SET "$c.Rule.[SourceInterface=$interface].SourceInterface" "$interface"
			cmclient SET "$c.Rule.[DestInterface=$interface].DestInterface" "$interface"
		done
	fi
	exit 0
fi
if [ $# -eq 1 ] && [ "$1" = "init" ]; then
	help_iptables_all -N Firewall.LHigh
	help_iptables_all -N Firewall.LLow
	help_iptables_all -N FirewallIn.LHigh
	help_iptables_all -N FirewallIn.LLow
	refreshDefaultLevels
	cmclient -v tmp GETV Device.Firewall.Enable
	if [ "$tmp" = "true" ]; then
		cmclient -v tmp GETV Device.Firewall.Config
		cmclient -v al GETV Device.Firewall.AdvancedLevel
		linkLevels "$tmp" "$al" init
	fi
	refreshPortMapping
	refreshAllowLocalServices
	exit 0
fi
if [ "$obj" = "Device.Firewall" ]; then
	help_iptables_all -F Firewall
	help_iptables_all -F FirewallIn
	help_iptables_all -F FirewallOut
	if [ $changedEnable -eq 1 ]; then
		status="ON"
		[ "$newEnable" = "false" ] && status="OFF"
		logger -t "cm" -p 6 "Firewall ${status}"
		[ "$ipv6_global" = "true" ] && logger -t "cm" -p 6 "IPv6 Firewall ${status}"
	fi
	if [ "$changedEnable" = "1" -o "$changedConfig" = 1 -o "$changedAdvancedLevel" = 1 ]; then
		cmclient -v pme GETV $oldAdvancedLevel.PortMappingEnabled
		cmclient -v als GETV $oldAdvancedLevel.X_ADB_AllowLocalServices
		if [ "$newConfig" = "Advanced" -a "$newEnable" = "true" ]; then
			cmclient -v tmp GETV $newAdvancedLevel.PortMappingEnabled
			if [ "$tmp" = "true" ]; then
				[ "$changedAdvancedLevel" = 1 -a "$changedConfig" = 0 ] && [ "$pme" = "false" ] &&
					help_iptables -A ForwardAllow -j ForwardAllow_PortMapping
			else
				[ "$changedAdvancedLevel" = 0 -o "$changedConfig" = 1 ] || [ "$pme" = "true" ] &&
					help_iptables -D ForwardAllow -j ForwardAllow_PortMapping
			fi
			cmclient -v tmp GETV $newAdvancedLevel.X_ADB_AllowLocalServices
			if [ "$tmp" = "true" ]; then
				if [ "$changedAdvancedLevel" = 1 -a "$changedConfig" = 0 ] && [ "$als" = "false" ]; then
					help_iptables_all -D ServicesIn -j ServicesIn_LocalACLServices
					help_iptables_all -D OutputAllow -j OutputAllow_LocalACLServices
					help_iptables_all -A ServicesIn -j ServicesIn_LocalServices
					help_iptables_all -A OutputAllow -j OutputAllow_LocalServices
				fi
			else
				if [ "$changedAdvancedLevel" = 0 -o "$changedConfig" = 1 ] || [ "$als" = "true" ]; then
					help_iptables_all -D ServicesIn -j ServicesIn_LocalServices
					help_iptables_all -D OutputAllow -j OutputAllow_LocalServices
					help_iptables_all -A ServicesIn -j ServicesIn_LocalACLServices
					help_iptables_all -A OutputAllow -j OutputAllow_LocalACLServices
				fi
			fi
		elif [ "$oldConfig" = "Advanced" ]; then
			refreshDefaultLevels
			[ "$pme" = "false" ] && help_iptables -A ForwardAllow -j ForwardAllow_PortMapping
			if [ "$als" = "false" ]; then
				help_iptables_all -D ServicesIn -j ServicesIn_LocalACLServices
				help_iptables_all -D OutputAllow -j OutputAllow_LocalACLServices
				help_iptables_all -A ServicesIn -j ServicesIn_LocalServices
				help_iptables_all -A OutputAllow -j OutputAllow_LocalServices
			fi
		fi
	fi
	[ "$newEnable" = "false" ] && exit 0
	linkLevels "$newConfig" "$newAdvancedLevel"
	exit 0
fi
isChainLooped() {
	searchLoopedRule "$1"
	[ 1 -eq $? ] && cmclient -u Firewall SET "$1".Status Error_Misconfigured
}
levelCreateChains() {
	help_iptables_all -N Firewall.L"${obj##*.}"
	help_iptables_all -N FirewallIn.L"${obj##*.}"
	help_iptables_all -N FirewallOut.L"${obj##*.}"
	cmclient -v chainID ADD Device.Firewall.Chain
	if [ "$user" != "CWMP" ]; then
		cmclient -u Firewall SET Device.Firewall.Chain.${chainID}.Creator UserInterface
		cmclient -u Firewall SET Device.Firewall.Chain.${chainID}.Enable true
	fi
	help_iptables_all -A Firewall.L"${obj##*.}" -j Firewall.C${chainID}
	help_iptables_all -A FirewallIn.L"${obj##*.}" -j FirewallIn.C${chainID}
	help_iptables_all -A FirewallOut.L"${obj##*.}" -j FirewallOut.C${chainID}
	cmclient -u Firewall SET "$obj".Chain Device.Firewall.Chain.${chainID}
}
levelCreate() {
	maxOrder=0
	cmclient -v l GETO Device.Firewall.Level
	for l in $l; do
		if [ "$l" != "$obj" ]; then
			cmclient -v o GETV "${l}.Order"
			if [ -n "$o" ] && [ $o -gt $maxOrder ]; then
				maxOrder=$o
			fi
		fi
	done
	cmclient -u Firewall SET ${obj}.Order $((maxOrder + 1))
	levelCreateChains
}
levelDeleteChains() {
	for a in F X; do
		help_iptables_all -"${a}" Firewall.L${obj##*.}
		help_iptables_all -"${a}" FirewallIn.L${obj##*.}
		help_iptables_all -"${a}" FirewallOut.L${obj##*.}
	done
}
levelDelete() {
	local l tmp
	cmclient -v l GETO Device.Firewall.Level
	for l in $l; do
		if [ "$l" != "$obj" ]; then
			cmclient -v prevOrder GETV "$l".Order
			[ $prevOrder -gt $oldOrder ] &&
				cmclient -u Firewall SET "$l".Order $((prevOrder - 1))
		fi
	done
	cmclient -v tmp GETV $oldAdvancedLevel.PortMappingEnabled
	[ "$tmp" = "false" ] && help_iptables -A ForwardAllow -j ForwardAllow_PortMapping
	cmclient -v tmp GETV Device.Firewall.AdvancedLevel
	if [ "$obj" = "$tmp" ]; then
		cmclient SETE Device.Firewall.AdvancedLevel ""
		cmclient SET Device.Firewall.Config Low
	fi
	levelDeleteChains
}
if [ "${obj%.*}" = "Device.Firewall.Level" ]; then
	case "$op" in
	a)
		levelCreate
		;;
	d)
		levelDelete
		;;
	s)
		if [ $changedOrder -eq 1 ]; then
			cmclient -v l GETO Device.Firewall.Level.[Order=$newOrder]
			for l in $l; do
				if [ "$l" != "$obj" ]; then
					cmclient -v b GETO Device.Firewall.Level
					for b in $b; do
						if [ "$b" != "$obj" ]; then
							cmclient -v prevOrder GETV "$b".Order
							if [ $prevOrder -eq $newOrder ]; then
								cmclient -u Firewall SET "$b".Order $((prevOrder + 1))
								break
							fi
						fi
					done
					break
				fi
			done
		fi
		if [ $changedChain -eq 1 ] || [ $changedDefaultPolicy -eq 1 ]; then
			help_iptables_all -F Firewall.L${obj##*.}
			help_iptables_all -A Firewall.L${obj##*.} -j Firewall.C${newChain##*.}
			help_iptables_all -A Firewall.L${obj##*.} \
				-j $(echo "$newDefaultPolicy" | tr '[a-z]' '[A-Z]')
			help_iptables_all -F FirewallIn.L${obj##*.}
			help_iptables_all -A FirewallIn.L${obj##*.} -j FirewallIn.C${newChain##*.}
			help_iptables_all -A FirewallIn.L${obj##*.} \
				-j $(echo "$newDefaultPolicy" | tr '[a-z]' '[A-Z]')
			help_iptables_all -F FirewallOut.L${obj##*.}
			help_iptables_all -A FirewallOut.L${obj##*.} -j FirewallOut.C${newChain##*.}
			help_iptables_all -A FirewallOut.L${obj##*.} \
				-j $(echo "$newDefaultPolicy" | tr '[a-z]' '[A-Z]')
		fi
		cmclient -v tmp GETV Device.Firewall.AdvancedLevel
		cmclient -v config GETV Device.Firewall.Config
		if [ "$config" = "Advanced" -a "$tmp" = "$obj" ]; then
			if [ $changedPortMappingEnabled -eq 1 ]; then
				if [ "$newPortMappingEnabled" = "true" ]; then
					help_iptables -A ForwardAllow -j ForwardAllow_PortMapping
				else
					help_iptables -D ForwardAllow -j ForwardAllow_PortMapping
				fi
			fi
			if [ $changedDefaultLogPolicy -eq 1 ]; then
				: # TODO
			fi
			if [ $changedX_ADB_AllowLocalServices -eq 1 ]; then
				if [ "$newX_ADB_AllowLocalServices" = "true" ]; then
					help_iptables_all -D ServicesIn -j ServicesIn_LocalACLServices
					help_iptables_all -D OutputAllow -j OutputAllow_LocalACLServices
					help_iptables_all -A ServicesIn -j ServicesIn_LocalServices
					help_iptables_all -A OutputAllow -j OutputAllow_LocalServices
				else
					help_iptables_all -D ServicesIn -j ServicesIn_LocalServices
					help_iptables_all -D OutputAllow -j OutputAllow_LocalServices
					help_iptables_all -A ServicesIn -j ServicesIn_LocalACLServices
					help_iptables_all -A OutputAllow -j OutputAllow_LocalACLServices
				fi
			fi
		fi
		;;
	esac
	exit 0
fi
chainCreate() {
	help_iptables_all -N Firewall.C${obj##*.}
	help_iptables_all -N FirewallIn.C${obj##*.}
	help_iptables_all -N FirewallOut.C${obj##*.}
}
chainDelete() {
	local a x
	cmclient -v x GETO "Device.Firewall.Level.[Chain=$obj]"
	cmclient SET Device.Firewall.Chain.Rule.[TargetChain=$obj].TargetChain ""
	for x in $x; do
		help_iptables_all -D Firewall.L${x##*.} -j Firewall.C${obj##*.}
		help_iptables_all -D FirewallIn.L${x##*.} -j FirewallIn.C${obj##*.}
		help_iptables_all -D FirewallOut.L${x##*.} -j FirewallOut.C${obj##*.}
		cmclient -u Firewall SET $x.Chain ""
	done
	for a in F X; do
		help_iptables_all -${a} Firewall.C${obj##*.}
		help_iptables_all -${a} FirewallIn.C${obj##*.}
		help_iptables_all -${a} FirewallOut.C${obj##*.}
	done
}
fixRange() {
	s="$1"
	out=""
	set -f
	IFS=-
	for i in $s; do
		[ -n "$out" ] && out="$out:"
		out="$out$i"
	done
	unset IFS
	set +f
	echo -n "$out"
}
if [ "${obj%.*}" = "Device.Firewall.Chain" ]; then
	case "$op" in
	a)
		chainCreate
		;;
	d)
		chainDelete
		;;
	esac
	exit 0
fi
getIfName() {
	local intf="$1" ifname
	case "$intf" in
	Device.IPv6rd.InterfaceSetting.*)
		echo "6rdtun${intf##*.}"
		;;
	*)
		help_lowlayer_ifname_get ifname "$intf"
		echo "$ifname"
		;;
	esac
}
joinRules() {
	unset nextRule
	unset minOrder
	cmclient -v o GETO "$chain".Rule.[Order+$newOrder]
	for o in $o; do
		cmclient -v order GETV $o.Order
		if [ $order -eq $((newOrder + 1)) ]; then
			nextRule=$o
			break
		elif [ $order -le ${minOrder:-$order} ]; then
			nextRule=$o
			minOrder=$order
		fi
	done
	if [ -n "$nextRule" ]; then
		nextRuleID="${nextRule##*.}"
		for s in "" "Out" "In"; do
			help_iptables_all -A Firewall${s}.C${chainID}.R${ruleID} -g \
				Firewall${s}.C${chainID}.R${nextRuleID}
		done
	fi
}
ruleRefresh() {
	help_iptables_all -F Firewall.C"${chainID}".R"${ruleID}"
	help_iptables_all -F FirewallIn.C"${chainID}".R"${ruleID}"
	help_iptables_all -F FirewallOut.C"${chainID}".R"${ruleID}"
	if [ "$newEnable" = "false" ]; then
		cmclient -u Firewall SET "$obj".Status Disabled
		return
	fi
	if [ -n "$newX_ADB_HostName" ]; then
		cmclient -v host GETO Device.Hosts.Host.[HostName=$newX_ADB_HostName]
		if [ -n "$host" ]; then
			cmclient -v hostnameIP GETV $host.IPAddress
		fi
		if [ -z "$hostnameIP" ]; then
			cmclient -u Firewall SET "$obj".Status Disabled
			return
		fi
	fi
	if [ "$newLog" = "true" ]; then
		:
	fi
	status=""
	if [ -n "$newX_ADB_ConnectionStatus" ]; then
		status=" -m state --state $newX_ADB_ConnectionStatus"
	fi
	stage=""
	sif=""
	if [ "$newSourceAllInterfaces" = "false" ]; then
		if [ -z "$newSourceInterface" ]; then
			cmclient -u Firewall SET "$obj".Status Error_Misconfigured
			return
		fi
		if [ "$newSourceInterface" = "X_ADB_Local" ]; then
			stage="Out"
		else
			cmclient -v tmp GETO $newSourceInterface
			if [ -z "$tmp" ]; then
				cmclient -u Firewall SET "$obj".SourceInterface ""
				cmclient -u Firewall SET "$obj".Status Error_Misconfigured
				return
			fi
			[ "$newSourceInterfaceExclude" = "true" ] && sif="!"
			sifName=$(getIfName "$newSourceInterface")
			if isEnslaved "$sifName"; then
				sif="-m physdev ${sif} --physdev-in $sifName"
			else
				sif="${sif} -i $sifName"
			fi
		fi
	fi
	dif=""
	if [ "$newDestAllInterfaces" = "false" ]; then
		if [ -z "$newDestInterface" ]; then
			cmclient -u Firewall SET "$obj".Status Error_Misconfigured
			return
		fi
		if [ "$newDestInterface" = "X_ADB_Local" ]; then
			if [ -n "$stage" ]; then
				cmclient -u Firewall SET "$obj".Status Error_Misconfigured
				return
			fi
			stage="In"
		else
			cmclient -v tmp GETO $newDestInterface
			if [ -z "$tmp" ]; then
				cmclient -u Firewall SET "$obj".DestInterface ""
				cmclient -u Firewall SET "$obj".Status Error_Misconfigured
				return
			fi
			[ "$newDestInterfaceExclude" = "true" ] && dif="!"
			difName=$(getIfName "$newDestInterface")
			if isEnslaved "$difName"; then
				dif="${dif} -m physdev --physdev-out $difName --physdev-is-bridged"
			else
				dif="${dif} -o $difName"
			fi
		fi
	fi
	if [ "$newTarget" = "TargetChain" ]; then
		if [ -n "$newTargetChain" ]; then
			tgt="-j Firewall${stage}.C${newTargetChain##*.}"
		else
			cmclient -u Firewall SET "$obj".Status Error_Misconfigured
			return
		fi
	else
		tgt="-j $(help_uppercase "$newTarget")"
	fi
	daddr=""
	if [ -n "$newDestIP" ]; then
		if [ "$newDestIPExclude" = "true" ]; then
			daddr="!"
		fi
		daddr="${daddr} -d $newDestIP"
		if [ -n "$newDestMask" ]; then
			daddr="${daddr}/${newDestMask#*/}"
		fi
	fi
	saddr=""
	if [ -n "$newX_ADB_SourceHost" ]; then
		cmclient -v hostaddr GETV ${newX_ADB_SourceHost}.IPAddress
	fi
	if [ -n "$hostaddr" ]; then
		saddr="-s $hostaddr"
	elif [ -n "$newSourceIP" ]; then
		if [ "$newSourceIPExclude" = "true" ]; then
			saddr="!"
		fi
		saddr="${saddr} -s $newSourceIP"
		if [ -n "$newSourceMask" ]; then
			saddr="${saddr}/${newSourceMask#*/}"
		fi
	elif [ -n "$newX_ADB_SourceIPRangeMin" ] && [ -n "$newX_ADB_SourceIPRangeMax" ]; then
		[ "$newSourceIPExclude" = true ] && sexcl="!" || sexcl=
		saddr="-m iprange $sexcl --src-range ${newX_ADB_SourceIPRangeMin}-${newX_ADB_SourceIPRangeMax}"
	elif [ -n "$newX_ADB_MACAddress" ]; then
		saddr="-m mac --mac-source ${newX_ADB_MACAddress}"
	fi
	dport=""
	sport=""
	proto=""
	dport2=""
	proto2=""
	if [ -n "$newX_ADB_Service" ]; then
		cmclient -v extport GETV $newX_ADB_Service.ExternalPort
		cmclient -v extportend GETV $newX_ADB_Service.ExternalPortEndRange
		cmclient -v addextport GETV $newX_ADB_Service.AdditionalExternalPort
		cmclient -v protocol GETV $newX_ADB_Service.Protocol
		if [ -n "$extportend" -a "$extportend" != "0" -a "$extportend" != "-1" ]; then
			ports="$protocol:$extport-$extportend"
		else
			ports="$protocol:$extport"
		fi
		if [ -n "$addextport" ]; then
			ports="$ports,$addextport"
		fi
		udpports=""
		tcpports=""
		set -f
		IFS=,
		for p in $ports; do
			case "$p" in
			UDP:*)
				[ -n "$udpports" ] && udpports="$udpports,"
				udpports="$udpports${p##UDP:}"
				;;
			TCP:*)
				[ -n "$tcpports" ] && tcpports="$tcpports,"
				tcpports="$tcpports${p##TCP:}"
				;;
			TCP/UDP:*)
				[ -n "$udpports" ] && udpports="$udpports,"
				udpports="$udpports${p##TCP/UDP:}"
				[ -n "$tcpports" ] && tcpports="$tcpports,"
				tcpports="$tcpports${p##TCP/UDP:}"
				;;
			esac
		done
		set +f
		unset IFS
		tcpports="$(fixRange $tcpports)"
		udpports="$(fixRange $udpports)"
		if [ -z "$udpports" -a -n "$tcpports" ]; then
			dport="-m multiport --dports $tcpports"
			proto="-p tcp"
		elif [ -n "$udpports" -a -z "$tcpports" ]; then
			dport="-m multiport --dports $udpports"
			proto="-p udp"
		elif [ -n "$udpports" -a -n "$tcpports" ]; then
			dport="-m multiport --dports $tcpports"
			proto="-p tcp"
			dport2="-m multiport --dports $udpports"
			proto2="-p udp"
		elif [ -n "$protocol" ]; then
			case "$protocol" in
			ICMP)
				proto="-p icmp"
				;;
			IGMP)
				proto="-p igmp"
				;;
			esac
		fi
	elif [ -n "$newProtocol" ] && [ "$newProtocol" != "-1" ]; then
		if [ "$newProtocolExclude" = "true" ]; then
			proto="! -p $newProtocol"
		else
			proto="-p $newProtocol"
			if [ "$newProtocol" = 51 -a "$newIPVersion" = 6 ]; then
				proto="-m ah"
			elif [ $newProtocol -eq 6 ] || [ $newProtocol -eq 17 ]; then
				if [ -n "$newDestPort" ] && [ "$newDestPort" != "-1" ]; then
					if [ "$newDestPortExclude" = "true" ]; then
						dport="! "
					fi
					if [ -n "$newDestPortRangeMax" ] && [ "$newDestPortRangeMax" != "-1" ] && [ "$newDestPortRangeMax" != "$newDestPort" ]; then
						dport="-m multiport ${dport} --dports ${newDestPort}:${newDestPortRangeMax}"
					else
						dport="${dport} --dport $newDestPort"
					fi
				fi
				if [ -n "$newSourcePort" ] && [ "$newSourcePort" != "-1" ]; then
					if [ "$newSourcePortExclude" = "true" ]; then
						sport="! "
					fi
					if [ -n "$newSourcePortRangeMax" ] && [ "$newSourcePortRangeMax" != "-1" ] && [ "$newSourcePortRangeMax" != "$newSourcePort" ]; then
						sport="-m multiport ${sport} --sports ${newSourcePort}:${newSourcePortRangeMax}"
					else
						sport="${sport} --sport $newSourcePort"
					fi
				fi
				if [ $newProtocol -eq 6 ]; then
					watchFlags=""
					setFlags=""
					if [ -n "$newX_ADB_TCPFlagsSet" ]; then
						flags="--tcp-flags"
						set -f
						IFS=","
						set -- $newX_ADB_TCPFlagsSet
						unset IFS
						set +f
						for f; do
							watchFlags="${watchFlags},${f}"
							setFlags="${setFlags},${f}"
						done
					fi
					if [ -n "$newX_ADB_TCPFlagsUnset" ]; then
						flags="--tcp-flags"
						set -f
						IFS=","
						set -- $newX_ADB_TCPFlagsUnset
						unset IFS
						set +f
						for f; do
							watchFlags="${watchFlags},${f}"
						done
					fi
					[ -n "$flags" ] && : ${watchFlags:="NONE"} ${setFlags:="NONE"}
				fi
			fi
		fi
	fi
	local dscp="" dscp_exclude=""
	if [ -n "$newDSCP" ] && [ "$newDSCP" != "-1" ]; then
		[ "$newDSCPExclude" = "true" ] && dscp_exclude="!"
		dscp="-m dscp "$dscp_exclude" --dscp ${newDSCP}"
	fi
	l3type_y=""
	if [ -n "$newX_ADB_AddressingMatch" ]; then
		set -f
		IFS=","
		set -- $newX_ADB_AddressingMatch
		unset IFS
		set +f
		for t; do
			l3type_y="${l3type_y} -m pkttype --pkt-type ${t}"
		done
	fi
	l3type_n=""
	if [ -n "$newX_ADB_AddressingNoMatch" ]; then
		set -f
		IFS=","
		set -- $newX_ADB_AddressingNoMatch
		unset IFS
		set +f
		for t; do
			l3type_y="${l3type_y} -m pkttype ! --pkt-type ${t}"
		done
	fi
	[ "$newX_ADB_ForwardingPolicy" != -1 ] && mark="-m mark --mark $newX_ADB_ForwardingPolicy/0xff"
	case "$newIPVersion" in
	4)
		if [ "$newLog" = "true" ]; then
			help_iptables -A Firewall${stage}.C${chainID}.R${ruleID} -j LOG --log-prefix "\"FIREWALL: match C${chainID}R${ruleID} - \""\
			--log-level 6 ${sif} ${dif} ${daddr} ${saddr} \
				${proto} ${dport} ${sport} ${dscp} \
				${flags} ${watchFlags} ${setFlags} ${l3type_y} ${l3type_n} ${status} ${mark}
		fi
		help_iptables -A Firewall${stage}.C${chainID}.R${ruleID} ${tgt} \
			${sif} ${dif} ${daddr} ${saddr} \
			${proto} ${dport} ${sport} ${dscp} \
			${flags} ${watchFlags} ${setFlags} ${l3type_y} ${l3type_n} ${status} ${mark}
		if [ -n "$proto2" ]; then
			help_iptables -A Firewall${stage}.C${chainID}.R${ruleID} ${tgt} \
				${sif} ${dif} ${daddr} ${saddr} \
				${proto2} ${dport2} ${sport2} ${dscp} \
				${flags} ${watchFlags} ${setFlags} ${l3type_y} ${l3type_n} ${status} ${mark}
		fi
		;;
	6)
		[ "$newX_ADB_EndpointFiltering" = true ] && tgt="-j ENDPOINT"
		if [ "$newLog" = "true" ]; then
			help_ip6tables -A Firewall${stage}.C${chainID}.R${ruleID} -j LOG --log-prefix "\"FIREWALL: match C${chainID}R${ruleID} - \""\
			--log-level 6 ${sif} ${dif} ${daddr} ${saddr} \
				${proto} ${dport} ${sport} ${dscp} \
				${flags} ${watchFlags} ${setFlags} ${l3type_y} ${l3type_n} ${status} ${mark}
		fi
		help_ip6tables -A Firewall${stage}.C${chainID}.R${ruleID} ${tgt} \
			${sif} ${dif} ${daddr} ${saddr} \
			${proto} ${dport} ${sport} ${dscp} \
			${flags} ${watchFlags} ${setFlags} ${l3type_y} ${l3type_n} ${status} ${mark}
		if [ -n "$proto2" ]; then
			help_ip6tables -A Firewall${stage}.C${chainID}.R${ruleID} ${tgt} \
				${sif} ${dif} ${daddr} ${saddr} \
				${proto2} ${dport2} ${sport2} ${dscp} \
				${flags} ${watchFlags} ${setFlags} ${l3type_y} ${l3type_n} ${status} ${mark}
		fi
		;;
	-1)
		if [ "$newLog" = "true" ]; then
			help_iptables_all -A Firewall${stage}.C${chainID}.R${ruleID} -j LOG --log-prefix "\"FIREWALL: match C${chainID}R${ruleID} - \""\
			--log-level 6 ${sif} ${dif} ${daddr} ${saddr} \
				${proto} ${dport} ${sport} ${dscp} \
				${flags} ${watchFlags} ${setFlags} ${l3type_y} ${l3type_n} ${status} ${mark}
		fi
		help_iptables_all -A Firewall${stage}.C${chainID}.R${ruleID} ${tgt} \
			${sif} ${dif} ${daddr} ${saddr} \
			${proto} ${dport} ${sport} ${dscp} \
			${flags} ${watchFlags} ${setFlags} ${l3type_y} ${l3type_n} ${status} ${mark}
		if [ -n "$proto2" ]; then
			help_iptables_all -A Firewall${stage}.C${chainID}.R${ruleID} ${tgt} \
				${sif} ${dif} ${daddr} ${saddr} \
				${proto2} ${dport2} ${sport2} ${dscp} \
				${flags} ${watchFlags} ${setFlags} ${l3type_y} ${l3type_n} ${status} ${mark}
		fi
		;;
	esac
	cmclient -u Firewall SET "$obj".Status Enabled
}
case "$obj" in
Device.Firewall.Chain.*.Rule.*)
	chain="${obj%.Rule.*}"
	chainID="${chain##*.}"
	ruleID="${obj##*.}"
	case "$op" in
	a)
		if [ -z "$newCreationDate" ]; then
			sysdate=$(date -u +%FT%TZ)
			cmclient SETE "$obj.CreationDate" "$sysdate"
		fi
		help_iptables_all -N Firewall.C${chainID}.R${ruleID}
		help_iptables_all -N FirewallIn.C${chainID}.R${ruleID}
		help_iptables_all -N FirewallOut.C${chainID}.R${ruleID}
		maxOrder=0
		cmclient -v r GETO "$chain".Rule
		for r in $r; do
			if [ "$r" != "$obj" ]; then
				cmclient -v o GETV "$r.Order"
				[ $o -gt $maxOrder ] && maxOrder=$o
			fi
		done
		newOrder=$((maxOrder + 1))
		cmclient -u Firewall SET "${obj}".Order $newOrder
		cmclient -v prevRule GETO "$chain.Rule.[Order=$maxOrder]"
		if [ -n "$prevRule" ]; then
			prevRuleID="${prevRule##*.}"
			help_iptables_all -A Firewall.C${chainID}.R${prevRuleID} -g Firewall.C${chainID}.R${ruleID}
			help_iptables_all -A FirewallIn.C${chainID}.R${prevRuleID} -g FirewallIn.C${chainID}.R${ruleID}
			help_iptables_all -A FirewallOut.C${chainID}.R${prevRuleID} -g FirewallOut.C${chainID}.R${ruleID}
		fi
		if [ $newOrder -eq 1 ]; then
			help_iptables_all -F Firewall.C$chainID
			help_iptables_all -F FirewallIn.C$chainID
			help_iptables_all -F FirewallOut.C$chainID
			help_iptables_all -A Firewall.C$chainID \
				-g Firewall.C$chainID.R$ruleID
			help_iptables_all -A FirewallIn.C$chainID \
				-g FirewallIn.C$chainID.R$ruleID
			help_iptables_all -A FirewallOut.C$chainID \
				-g FirewallOut.C$chainID.R$ruleID
		fi
		joinRules
		;;
	d)
		cmclient -v prevRule GETO "$chain.Rule.[Order=$((oldOrder - 1))]"
		if [ -n "$prevRule" ]; then
			prevRuleID="${prevRule##*.}"
			help_iptables_all -D Firewall.C${chainID}.R${prevRuleID} -g Firewall.C${chainID}.R${ruleID}
			help_iptables_all -D FirewallIn.C${chainID}.R${prevRuleID} -g FirewallIn.C${chainID}.R${ruleID}
			help_iptables_all -D FirewallOut.C${chainID}.R${prevRuleID} -g FirewallOut.C${chainID}.R${ruleID}
			cmclient -v nextRule GETO "$chain.Rule.[Order=$((oldOrder + 1))]"
			if [ -n "$nextRule" ]; then
				nextRuleID="${nextRule##*.}"
				help_iptables_all -A Firewall.C${chainID}.R${prevRuleID} -g Firewall.C${chainID}.R${nextRuleID}
				help_iptables_all -A FirewallIn.C${chainID}.R${prevRuleID} -g FirewallIn.C${chainID}.R${nextRuleID}
				help_iptables_all -A FirewallOut.C${chainID}.R${prevRuleID} -g FirewallOut.C${chainID}.R${nextRuleID}
			fi
		fi
		cmclient -v r GETO "$chain.Rule.[Order+$oldOrder]"
		for r in $r; do
			cmclient -v o GETV "$r".Order
			cmclient -u Firewall SET "$r."Order $((o - 1))
		done
		if [ $oldOrder -eq 1 ]; then
			cmclient -v r GETO "$chain.Rule.[Order=1]"
			for r in $r; do
				if [ "$r" != "$obj" ]; then
					firstRuleID="${r##*.}"
				fi
			done
			help_iptables_all -D Firewall.C${chainID} -g Firewall.C${chainID}.R${ruleID}
			help_iptables_all -D FirewallIn.C${chainID} -g FirewallIn.C${chainID}.R${ruleID}
			help_iptables_all -D FirewallOut.C${chainID} -g FirewallOut.C${chainID}.R${ruleID}
			help_iptables_all -F Firewall.C$chainID
			help_iptables_all -F FirewallIn.C$chainID
			help_iptables_all -F FirewallOut.C$chainID
			if [ -n "$firstRuleID" ]; then
				help_iptables_all -A Firewall.C$chainID \
					-g Firewall.C$chainID.R$firstRuleID
				help_iptables_all -A FirewallIn.C$chainID \
					-g FirewallIn.C$chainID.R$firstRuleID
				help_iptables_all -A FirewallOut.C$chainID \
					-g FirewallOut.C$chainID.R$firstRuleID
			fi
		fi
		for a in F X; do
			help_iptables_all -${a} Firewall.C${chainID}.R${ruleID}
			help_iptables_all -${a} FirewallIn.C${chainID}.R${ruleID}
			help_iptables_all -${a} FirewallOut.C${chainID}.R${ruleID}
		done
		;;
	s)
		if [ $changedOrder -eq 1 ]; then
			help_sort_orders "$obj" "$oldOrder" "$newOrder" Firewall
			help_iptables_all
			cmclient SET -u "${tmpiptablesprefix##*/}" "$chain.Rule.[Order!$newOrder].[Enable=true].Enable" true
			cmclient SET -u "${tmpiptablesprefix##*/}" "$chain.Rule.[Order!$newOrder].[Enable=false].Enable" false
		fi
		if [ $changedOrder -eq 1 -o $setEnable -eq 1 ] && [ $newOrder -eq 1 ]; then
			help_iptables_all -F Firewall.C$chainID
			help_iptables_all -F FirewallIn.C$chainID
			help_iptables_all -F FirewallOut.C$chainID
			help_iptables_all -A Firewall.C$chainID \
				-g Firewall.C$chainID.R$ruleID
			help_iptables_all -A FirewallIn.C$chainID \
				-g FirewallIn.C$chainID.R$ruleID
			help_iptables_all -A FirewallOut.C$chainID \
				-g FirewallOut.C$chainID.R$ruleID
		fi
		ruleRefresh
		joinRules
		isChainLooped $obj
		[ "$user" != noConnTrackFlush ] && : >"$tmpiptablesprefix/do_flush"
		;;
	esac
	;;
esac
exit 0
