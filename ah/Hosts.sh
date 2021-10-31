#!/bin/sh
[ "$user" = "yacs" ] && exit 0
. /etc/ah/helper_hosts.sh
if [ "$changedLayer1Interface" = "1" ]; then
	cmclient -v mac_addr GETV "$obj.[Layer1Interface>Device.Ethernet.Interface].PhysAddress"
	[ -n "$mac_addr" ] && logger -t "cm" -p 7 "ETH: added MAC ${mac_addr}"
	cmclient -v ip GETV $obj.IPv4Address.IPAddress
	for ip in ${ip:-$newIPAddress}; do
		echo "$ip" >/proc/net/nf_conntrack_flush
	done
fi
if [ "$changedActive" = "1" -o "$changedIPAddress" = "1" ]; then
	local link="disconnected"
	local action="added"
	[ "$newActive" = "true" ] && link="added" || action="removed"
	cmclient -v ipv6_global GETV "Device.IP.IPv6Enable"
	if [ "$ipv6_global" = "true" ]; then
		cmclient -v dhcp6_enable GETV "Device.DHCPv6.Server.Enable"
		cmclient -v ip6_vector GETV "$obj".IPv6Address.*.IPAddress
	fi
	[ -n "$newPhysAddress" ] && mac_addr="$newPhysAddress" || cmclient -v mac_addr GETV "$obj".PhysAddress
	[ -n "$newLayer1Interface" ] && l_if="$newLayer1Interface" || cmclient -v l_if GETV "$obj".Layer1Interface
	cmclient -v dhcp4_enable GETV "Device.DHCPv4.Server.Enable"
	cmclient -v ip4_vector GETV "$obj".IPv4Address.*.IPAddress
	case "$l_if" in
	Device.Ethernet.Interface.*)
		[ "$changedLayer1Interface" = "1" ] || logger -t "cm" -p 7 "ETH: ${action} MAC ${mac_addr}"
		;;
	esac
	if [ "$newActive" = "true" ]; then
		if [ "$dhcp4_enable" = "true" ]; then
			for addr in $ip4_vector; do
				cmclient -v dhcp4_lease GETO "Device.DHCPv4.Server.Pool.*.Client.*.IPv4Address.*.[IPAddress=$addr]"
				if [ -z "$dhcp4_lease" ]; then
					cmclient -v dhcp4_lease GETV "Device.DHCPv4.Server.Pool.[Enable=true].[Interface=${newLayer3Interface}].StaticAddress.[Chaddr!$mac_addr].[Yiaddr=$addr].[Enable=true].Chaddr"
					[ -z "$dhcp4_lease" ] && logger -t "cm" -p 7 "LAN: ${link} host IP ${addr} MAC ${mac_addr} (static)" ||
						logger -t "cm" -p 4 "LAN: warning - ${link} host with static IP ${addr} MAC ${mac_addr} equal to DHCP static entry reserved for MAC $dhcp4_lease"
					[ -n "$dhcp4_lease" ] && logger -t "dhcps" -p 4 "ARS 7 - LAN: host MAC ${mac_addr} found with with static IP ${addr} which is reserved for MAC $dhcp4_lease"
					cmclient -v preas_obj GETV "Device.DHCPv4.Server.Pool.[Enable=true].StaticAddress.[Chaddr=$mac_addr].[Yiaddr!$addr].[Enable=true].Yiaddr"
					[ -n "$preas_obj" ] && logger -t "dhcps" -p daemon.warning "ARS 8 - LAN host MAC ${mac_addr} found with IP ${addr}, instead of DHCP reserved IP $preas_obj"
				else
					cmclient -v preas_obj GETO "Device.DHCPv4.Server.Pool.*.StaticAddress.*.[Yiaddr=$addr].[Chaddr=$mac_addr].[Enable=true]"
					if [ -n "$preas_obj" ]; then
						[ "$link" = "added" ] && rel="" || rel="released "
						logger -t "cm" -p 7 "LAN: ${rel}preassigned IP $addr MAC $mac_addr"
					else
						cmclient -v preas_obj GETV "Device.DHCPv4.Server.Pool.[Enable=true].StaticAddress.[Chaddr=$mac_addr].[Enable=true].Yiaddr"
						[ -n "$preas_obj" ] && logger -t "cm" -p 4 "LAN: warning - ${link} host IP ${addr} MAC ${mac_addr}, instead of reserved IP $preas_obj (DHCP)" || logger -t "cm" -p 7 "LAN: ${link} host IP ${addr} MAC ${mac_addr} (DHCP)"
						if [ -n "$preas_obj" ]; then
							logger -t "dhcps" -p daemon.warning "ARS 8 - LAN host MAC ${mac_addr} found with IP ${addr}, instead of DHCP reserved IP $preas_obj"
						fi
					fi
				fi
			done
		else
			for addr in $ip4_vector; do
				logger -t "cm" -p 7 "LAN: ${link} host IP ${addr} MAC ${mac_addr} (static)"
			done
		fi
	fi
	if [ "$ipv6_global" = "true" -a "$dhcp6_enable" = "true" ]; then
		for addr in $ip6_vector; do
			cmclient -v dhcp6_lease GETO "Device.DHCPv6.Server.Pool.*.Client.*.IPv6Address.*.[IPAddress=$addr]"
			[ -z "$dhcp6_lease" ] && continue
			logger -t "cm" -p 7 "LAN: ${link} host IPv6 ${addr} MAC ${mac_addr} (DHCPv6 PD)"
		done
	fi
fi
[ "$changedHostName" != "1" ] && [ "$changedX_ADB_Domain" != "1" ] && [ "$changedIPAddress" != "1" ] && [ "$op" != "d" ] && [ "$1" != "init" ] &&
	exit 0
rm -f /tmp/dns/local_relay_drop* /tmp/dns/local_server_drop*
mkdir -p /tmp/dns
echo "127.0.0.1 localhost localhost." >/tmp/hosts.tmp
echo "::1 ip6-localhost ip6-loopback" >>/tmp/hosts.tmp
echo "fe00::0 ip6-localnet" >>/tmp/hosts.tmp
echo "ff00::0 ip6-mcastprefix" >>/tmp/hosts.tmp
echo "ff02::1 ip6-allnodes" >>/tmp/hosts.tmp
echo "ff02::2 ip6-allrouters" >>/tmp/hosts.tmp
cmclient -v local_domain GETV "Device.Hosts.X_ADB_HostName.[AddressSource=X_ADB_CPEName].[X_ADB_Domain!].X_ADB_Domain"
for local_domain in $local_domain; do
	break
done
names_list=""
cmclient -v host GETO 'Device.Hosts.X_ADB_HostName.*.[HostName!]'
for host in $host; do
	[ "$op" = "d" -a "$obj" = "$host" ] && continue
	help_resolve_hostname "$host" "$local_domain" >>/tmp/hosts.tmp
	cmclient -v as GETV "${host}.AddressSource"
	if [ "$as" = "X_ADB_CPEName" ]; then
		cmclient -v name GETV "${host}.HostName"
		cmclient -v domain GETV "${host}.X_ADB_Domain"
		echo "$name" >/proc/sys/kernel/hostname
		echo "$domain" >/proc/sys/kernel/domainname
		hostname "$name"
		names_list="${names_list},${name}${domain}"
		if [ -n "$domain" ]; then
			echo "255 ${domain} drop 0 * *" >/tmp/dns/local_relay_drop_${domain}
			echo "255 ${domain} drop 0 lo *" >/tmp/dns/local_server_drop_${domain}
		fi
	fi
done
cmclient -v host GETO 'Device.Hosts.Host.*.[HostName!]'
for host in $host; do
	[ "$op" = "d" -a "$obj" = "$host" ] && continue
	help_resolve_hostname "$host" "$local_domain" >>/tmp/hosts.tmp
done
cat /tmp/hosts.tmp >/tmp/hosts
rm -f /tmp/hosts.tmp
[ -n "${names_list}" ] && echo ${names_list#,} >/tmp/dns/local
if [ "$1" != "init" ]; then
	case "$obj" in
	Device.Hosts.X_ADB_HostName.*)
		cmclient SET 'Device.UserInterface.RemoteAccess.X_ADB_Reset' 'true'
		cmclient SET 'Device.UserInterface.X_ADB_LocalAccess.Reset' 'true'
		;;
	esac
fi
[ "$op" != "d" ] && exit 0
cmclient -v hosts GETO ManagementServer.ManageableDevice
for o in $hosts; do
	cmclient -v list GETV "$o".Host
	case "$list" in
	"$obj")
		cmclient DEL "$o"
		;;
	*"$obj"*)
		host=""
		set -f
		IFS=","
		set -- $list
		unset IFS
		set +f
		for h; do
			[ "$h" = "$obj" ] || host="${host:+$host,}$h"
		done
		cmclient SET "$o".Host "$host"
		;;
	esac
done
if [ "$newIPAddress" != "" -a "$newLayer3Interface" != "" ]; then
	cmclient -v ifname GETV "%(${newLayer3Interface}.LowerLayers).Name"
	[ -n "$ifname" ] && ip neigh del "$newIPAddress" dev "$ifname"
fi
exit 0
