#!/bin/sh
AH_NAME="NeighborDiscovery"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "boot" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/helper_ifname.sh
service_config() {
	local ifname
	local ipv6_iface_enable
	help_lowlayer_ifname_get ifname "$newInterface"
	cmclient -v ipv6_iface_enable GETV $newInterface.IPv6Enable
	if [ -z "$ifname" -o "$ipv6_glob_enable" = "false" -o "$ipv6_iface_enable" = "false" ]; then
		cmclient SETE $obj.Status Error_Misconfigured
		return
	fi
	local base="/proc/sys/net/ipv6/conf/$ifname"
	if [ "$newEnable" = "true" ]; then
		if [ -z "$newMaxRtrSolicitations" ] || [ -z "$newRtrSolicitationInterval" ] || [ -z "$newInterface" ]; then
			cmclient SET -u $AH_NAME$obj $obj.Status Error_Misconfigured
			return
		fi
		[ ! -d "$base" ] && return
		echo "$newRtrSolicitationInterval" >$base/router_solicitation_interval
		local glob_enable
		cmclient -v glob_enable GETV "Device.NeighborDiscovery.Enable"
		if [ "$newRSEnable" = "true" ] && [ "$glob_enable" = "true" ]; then
			echo "$newMaxRtrSolicitations" >$base/router_solicitations
			echo "1" >$base/router_solicitation_send
		else
			echo "0" >$base/router_solicitations
		fi
		cmclient SET -u $AH_NAME$obj $obj.Status Enabled
		[ "$setEnable" = "1" ] && echo "1" >$base/dad_transmits
	else
		echo "0" >$base/router_solicitations
		cmclient SET -u $AH_NAME$obj $obj.Status Disabled
		[ "$setEnable" = "1" ] && echo "0" >$base/dad_transmits
	fi
}
cmclient -v ipv6_glob_enable GETV "Device.IP.IPv6Enable"
case "$op" in
d)
	help_lowlayer_ifname_get ifname "$newInterface"
	ipv6_neigh_proc_enable "false" "$ifname"
	;;
s)
	if [ "$obj" = "Device.NeighborDiscovery" ]; then
		[ "$ipv6_glob_enable" = "false" ] && exit 0
		ipv6_neigh_proc_enable "$newEnable" "all"
		if [ "$newEnable" = "true" ]; then
			cmclient -v itf_list GETO "Device.NeighborDiscovery.InterfaceSetting"
			for entry in $itf_list; do
				cmclient -v status GETV "$entry.Enable"
				cmclient SET $entry.Enable "$status"
			done
		fi
	else
		service_config
	fi
	;;
esac
exit 0
