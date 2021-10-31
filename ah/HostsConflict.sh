#!/bin/sh
AH_NAME="HostsConflict"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" = "s" -o "$op" = "a" ] || exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
is_ip_addr_have_conflicts() {
	local ip_addr="$1" mac_addr="$2" gen_iface="$3" addr_kind="$4" postfix
	[ "$addr_kind" = "IPv6Address" ] && postfix="v6"
	cmclient -v is_conflict GETO "Device.Hosts.Host.*.[Active=true].[Layer3Interface=$gen_iface].[PhysAddress!$mac_addr].$addr_kind.*.[IPAddress=$ip_addr]"
	if [ -n "$is_conflict" ]; then
		logger -t "cm" -p 7 "LAN: conflict on IP$postfix $ip_addr"
	fi
}
case "$obj" in
Device.Hosts.Host.*.IPv4Address.*)
	if [ -n "$newIPAddress" ]; then
		cmclient -v gen_iface GETV "${obj%.IPv4Address.*}.Layer3Interface"
		cmclient -v mac_addr GETV "${obj%.IPv4Address.*}.PhysAddress"
		[ -n "$gen_iface" -a -n "$mac_addr" ] && is_ip_addr_have_conflicts "$newIPAddress" "$mac_addr" "$gen_iface" "IPv4Address"
	fi
	;;
Device.Hosts.Host.*.IPv6Address.*)
	if [ -n "$newIPAddress" ]; then
		cmclient -v gen_iface GETV "${obj%.IPv6Address.*}.Layer3Interface"
		cmclient -v mac_addr GETV "${obj%.IPv6Address.*}.PhysAddress"
		[ -n "$gen_iface" -a -n "$mac_addr" ] && is_ip_addr_have_conflicts "$newIPAddress" "$mac_addr" "$gen_iface" "IPv6Address"
	fi
	;;
Device.Hosts.Host.*)
	if [ "$changedActive" = "1" -a "$newActive" = "true" ]; then
		cmclient -v gen_iface GETV "$obj.Layer3Interface"
		cmclient -v mac_addr GETV "$obj.PhysAddress"
		if [ -n "$gen_iface" -a -n "$mac_addr" ]; then
			cmclient -v ip4_vector GETV "$obj.IPv4Address.*.IPAddress"
			for each_ip4 in $ip4_vector; do
				is_ip_addr_have_conflicts "$each_ip4" "$mac_addr" "$gen_iface" "IPv4Address"
			done
			cmclient -v ip6_vector GETV "$obj.IPv6Address.*.IPAddress"
			for each_ip6 in $ip6_vector; do
				is_ip_addr_have_conflicts "$each_ip6" "$mac_addr" "$gen_iface" "IPv6Address"
			done
		fi
	fi
	if [ "$changedActive" = "1" ]; then
		cmclient -v hn GETV $obj.HostName
		[ ${#hn} -gt 0 ] && cmclient SET "Device.NAT.PortMapping.[InternalClient=$hn].[Enable=true].Enable" "true"
	fi
	;;
esac
exit 0
