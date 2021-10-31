#!/bin/sh
AH_NAME="DMZ"
[ "$user" = "${AH_NAME}" ] && exit 0
src=0
if [ "$1" = 'refresh' ]; then
	src=1
elif [ "$obj" = 'Device.X_ADB_DMZ' ]; then
	if [ "$newEnable" = 'true' -a "$setEnable" = '1' -o "$setInterface" = '1' ]; then
		src=1
	else
		for i in Enable Interface IPAddress Layer1Interface Hairpinning UpstreamInterfaces InternalClient; do
			if eval [ \$changed${i} -eq 1 ]; then
				src=1
				break
			fi
		done
	fi
	[ $src -eq 0 ] && exit 0
elif [ "${obj%.*}" = "Device.Hosts.Host" ]; then
	src=1
fi
if [ $src -eq 1 ]; then
	. /etc/ah/helper_functions.sh
	. /etc/ah/helper_firewall.sh
	. /etc/ah/helper_ifname.sh
	. /etc/ah/target.sh
fi
update_interface() {
	local ipif ifstatus
	IFS=,
	for ipif in $newUpstreamInterfaces; do
		cmclient -v ifstatus GETV $ipif.Status
		if [ "$ifstatus" = "Up" ]; then
			cmclient SETE "$obj".Interface "$ipif"
			newInterface="$ipif"
			oldInterface=""
			changedInterface="1"
			setInterface="1"
			break
		fi
	done
	unset IFS
}
delete_SNAT_rules() {
	help_iptables -t nat -F SNAT_DMZ
	help_iptables -t nat -F DMZ_SNAT
}
delete_DMZ_rules() {
	local _lanIntf _wanip
	help_iptables -t nat -F DMZ
	delete_SNAT_rules
	help_iptables -t mangle -F DMZ
	help_iptables -t mangle -F DMZ
	help_iptables -t mangle -F DMZOut
	help_iptables -F ForwardAllow_DMZ
	cmclient -v _wanip GETV "${oldInterface}.IPv4Address.[Enable=true].IPAddress"
	for _wanip in $_wanip; do
		echo "$_wanip" >/proc/net/nf_conntrack_flush
	done
	help_lowlayer_ifname_get _lanIntf "$oldLayer1Interface"
	[ ${#_lanIntf} -ne 0 ] && eth_set_wan $_lanIntf false
}
update_DMZ_rules() {
	local _wanIntf _lanIntf wanip wanips snat_cmd_allowdst hairp_enable
	cmclient -v CWMPPort GETV Device.ManagementServer.[EnableCWMP=true].X_ADB_ConnectionRequestPort
	if [ "$newHairpinning" = "true" ]; then
		cmclient -v wanips GETV $newInterface.IPv4Address.+.[Enable=true].IPAddress
		for wanip in $wanips; do
			if help_is_valid_ip "$wanip"; then
				hairp_enable="true"
				snat_cmd_allowdst="${snat_cmd_allowdst:--d }$wanip,"
			fi
		done
		snat_cmd_allowdst=${snat_cmd_allowdst%,}
	fi
	delete_DMZ_rules
	help_lowlayer_ifname_get _wanIntf "$newInterface"
	help_lowlayer_ifname_get _lanIntf "$newLayer1Interface"
	help_iptables -t mangle -A DMZ -i $_wanIntf -m state --state NEW -j ACCEPT
	[ -n "$CWMPPort" ] &&
		help_iptables -t nat -A DMZ -i "$_wanIntf" -p tcp --dport $CWMPPort -j RETURN
	help_iptables -t nat -A DMZ -i "$_wanIntf" -d 224.0.0.0/4 -j RETURN
	help_iptables -t nat -A DMZ -i "$_wanIntf" -m state --state NEW -j DNAT --to-destination "$newIPAddress"
	if [ "$hairp_enable" = "true" ]; then
		help_iptables -t nat -A DMZ_SNAT $snat_cmd_allowdst -m state --state NEW -j DNAT --to-destination "$newIPAddress"
		help_iptables -t nat -A SNAT_DMZ -d $newIPAddress -m emark --mark 0x1/0x1 -j MASQUERADE
		help_iptables -t mangle -A DMZ -i br+ $snat_cmd_allowdst -j EMARK --set-mark 0x1/0x1
		help_iptables -t mangle -A DMZ -i br+ $snat_cmd_allowdst -j SKIPFC
	fi
	help_iptables -t mangle -I DMZ ! -i "$_wanIntf" -d "$newIPAddress" -j DROP
	help_iptables -A ForwardAllow_DMZ -i "$_wanIntf" -d "$newIPAddress" -j ACCEPT
	if [ "$hairp_enable" != "true" ]; then
		help_iptables -t mangle -A DMZOut ! -s "$newIPAddress" -j RETURN
		help_iptables -t mangle -A DMZOut ! -o "$_wanIntf" -j DROP
	else
		help_iptables -t mangle -A DMZOut -s "$newIPAddress" -o br+ -j SKIPFC
	fi
	help_iptables -t mangle -A DMZOut -j ACCEPT
	[ ${#_lanIntf} -ne 0 ] && eth_set_wan $_lanIntf true
}
refresh_host_ip() {
	local _ip= _val= _obj=$2
	[ ${#_obj} -eq 0 ] && _obj="Device.Hosts.Host"
	cmclient -v _val GETV Device.X_ADB_DMZ.InternalClient
	if [ ${#_val} -gt 0 ]; then
		if ipcalc -b "$_val" >/dev/null 2>&1; then
			_ip="$_val"
		else
			case "$_val" in
			*:*:*:*:*:*)
				cmclient -v _ip GETV "$_obj".[Active=true].[PhysAddress="$_val"].IPAddress
				[ ${#_ip} -gt 0 ] ||
					cmclient -v _ip GETV "$_obj".[PhysAddress="$_val"].IPAddress
				;;
			*)
				cmclient -v _ip GETV "$_obj".[Active=true].[HostName="$_val"].IPAddress
				[ ${#_ip} -gt 0 ] ||
					cmclient -v _ip GETV "$_obj".[HostName="$_val"].IPAddress
				;;
			esac
		fi
	fi
	if [ ${#_ip} -gt 0 ]; then
		cmclient SETE Device.X_ADB_DMZ.IPAddress "$_ip"
	else
		cmclient -v _ip GETV Device.X_ADB_DMZ.IPAddress
	fi
	newIPAddress="$_ip"
	return
}
service_read_manual() {
	cmclient -v newEnable GETV "Device.X_ADB_DMZ.Enable"
	cmclient -v newInterface GETV "Device.X_ADB_DMZ.Interface"
	cmclient -v newHairpinning GETV "Device.X_ADB_DMZ.Hairpinning"
}
update_layer1if() {
	local _lanIntf=""
	help_lowlayer_ifname_get _lanIntf "$oldLayer1Interface"
	[ ${#_lanIntf} -ne 0 ] && eth_set_wan $_lanIntf false
	help_lowlayer_ifname_get _lanIntf "$newLayer1Interface"
	[ ${#_lanIntf} -ne 0 ] && eth_set_wan $_lanIntf true
}
check_DMZ_params() {
	if [ -z "$newIPAddress" -o -z "$newInterface" ]; then
		cmclient SETE "$obj".Status Error_Misconfigured
		return 1
	fi
	cmclient -v newLayer1Interface GETV Device.Hosts.Host.[IPAddress=$newIPAddress].[Active=true].Layer1Interface
	cmclient SETE Device.X_ADB_DMZ.Layer1Interface "$newLayer1Interface"
	return 0
}
if [ "$1" = "refresh" ]; then
	service_read_manual
	[ "$newEnable" = "true" -a "$newHairpinning" = "true" -a "$newInterface" = "$obj" ] &&
		cmclient SET "Device.X_ADB_DMZ.Interface $newInterface"
	exit 0
fi
case "$obj" in
Device.X_ADB_DMZ)
	[ -z "$newInterface" -a "$changedInterface" = '0' ] && update_interface
	[ "$newStatus" = "Enabled" -a "$changedLayer1Interface" = '1' ] &&
		update_layer1if && exit 0
	if [ "$newEnable" = "true" ]; then
		refresh_host_ip
		if ! check_DMZ_params; then
			exit 0
		fi
		update_DMZ_rules
		[ "$newStatus" != "Enabled" ] && cmclient SETE "$obj".Status Enabled
	elif [ "$changedEnable" = "1" ]; then
		[ "$newStatus" != "Disabled" ] && cmclient SETE "$obj".Status Disabled
		delete_DMZ_rules
	fi
	;;
Device.Hosts.Host.*)
	my_host=0
	cmclient -v ip_addr GETV $obj.IPAddress
	cmclient -v h_na GETV $obj.HostName
	cmclient -v h_pa GETV $obj.PhysAddress
	cmclient -v d_ip GETV X_ADB_DMZ.IPAddress
	cmclient -v d_ic GETV X_ADB_DMZ.InternalClient
	[ ${#d_ic} -gt 0 ] && [ "$h_pa" = "$d_ic" -o "$h_na" = "$d_ic" ] && my_host=1
	refresh_host_ip "$obj"
	cmclient -v newInterface GETV "Device.X_ADB_DMZ.Interface"
	[ $my_host -eq 1 -a "$ip_addr" != "$d_ip" ] && update_DMZ_rules
	if [ "$ip_addr" = "$newIPAddress" ]; then
		cmclient -v hostActive GETV "$obj.Active"
		[ "$hostActive" = "false" ] && newLayer1Interface=""
		cmclient -v old_intf GETV Device.X_ADB_DMZ.Layer1Interface
		[ "$newLayer1Interface" != "$old_intf" ] &&
			cmclient SET Device.X_ADB_DMZ.Layer1Interface "$newLayer1Interface"
	fi
	;;
esac
exit 0
