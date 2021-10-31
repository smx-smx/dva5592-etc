#!/bin/sh
[ "$user" = "yacs" ] && exit 0
[ -f /tmp/upgrading.lock ] && [ "$op" != "g" ] && exit 0
[ -d /tmp/init_iptables ] && exit 0
remote=0
local=0
AH_NAME="Telnet"
INETD_CONF_FILE_LOCAL="/tmp/inetd/telnetd-local"
INETD_CONF_FILE_REMOTE="/tmp/inetd/telnetd-remote"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_ifname.sh
. /etc/ah/IPv6_helper_firewall.sh
cmclient -v ipv6_global GETV Device.IP.IPv6Enable
. /etc/ah/helper_firewall.sh
get_gid() {
	local group_user="$2" group_entry group_name gid x users_list
	while read group_entry; do
		group_name=${group_entry%%:*}
		if [ "$group_name" = "$group_user" ]; then
			IFS=":" read group_name x gid users_list <<-EOF
				$group_entry
			EOF
			eval $1='$gid'
			return
		fi
	done </etc/group
}
if [ "$obj" = "Device.X_ADB_TelnetServer.RemoteAccess" ]; then
	remote=1
	chainSuffix="Remote"
	get_gid gids remoteaccess
else
	local=1
	chainSuffix="Local"
	get_gid gids localaccess
fi
help_iptables -t nat -F NATSkip_Telnet${chainSuffix}
help_iptables_all -F Telnet${chainSuffix}In
help_iptables_all -F Telnet${chainSuffix}Out
help_iptables_all -A Telnet${chainSuffix}In ! -p tcp -j RETURN
help_iptables_all -A Telnet${chainSuffix}In -p tcp -m multiport ! --dports ${newPort} -j RETURN
help_iptables_all -A Telnet${chainSuffix}Out ! -p tcp -j RETURN
help_iptables_all -A Telnet${chainSuffix}Out -p tcp ! --sport ${newPort} -j RETURN
help_iptables -R Telnet${chainSuffix}In_ 1 -s 0.0.0.1/32 -d 0.0.0.1/32 -j DROP
help_iptables -R Telnet${chainSuffix}Out_ 1 -s 0.0.0.1/32 -d 0.0.0.1/32 -j DROP
help_ip6tables -R Telnet${chainSuffix}In_ 1 -s ::/128 -d ::/128 -j DROP
help_ip6tables -R Telnet${chainSuffix}Out_ 1 -s ::/128 -d ::/128 -j DROP
if [ "$changedX_ADB_AccessControlEnable" = "1" ]; then
	[ "$newX_ADB_AccessControlEnable" = "true" ] && cmd_line=-A || cmd_line=-D
	help_iptables_all $cmd_line ServicesIn_LocalACLServices -j Telnet${chainSuffix}In
	help_iptables_all $cmd_line OutputAllow_LocalACLServices -j Telnet${chainSuffix}Out
fi
if [ "$newEnable" = "false" ]; then
	[ $remote -eq 1 ] && rm ${INETD_CONF_FILE_REMOTE} >/dev/null 2>&1
	[ $local -eq 1 ] && rm ${INETD_CONF_FILE_LOCAL} >/dev/null 2>&1
	if [ "$changedEnable" = 1 -o "$changedX_ADB_AccessControlEnable" = 1 ]; then
		. /etc/ah/helper_conflicts.sh
		set -f
		IFS=","
		set -- $newInterfaces
		set +f
		unset IFS
		help_reconfigure_nat_conflicts "$@"
	fi
	exit 0
fi
if [ "$changedEnable" = 1 -o "$changedPort" = 1 -o "$changedInterfaces" = 1 -o "$changedX_ADB_AccessControlEnable" = 1 ]; then
	. /etc/ah/helper_conflicts.sh
	help_check_conflicts "$remote" "${newInterfaces}" "${newPort}" || exit 1
	set -f
	IFS=","
	set -- $newInterfaces
	set +f
	unset IFS
	help_reconfigure_nat_conflicts "$@"
	if [ "$changedInterfaces" = "1" ]; then
		set -f
		IFS=","
		set -- $oldInterfaces
		set +f
		unset IFS
		help_reconfigure_nat_conflicts "$@"
	fi
fi
listen=""
interfaces=""
listen6=""
if [ -n "$newInterfaces" ]; then
	set -f
	IFS=","
	set -- $newInterfaces
	set +f
	unset IFS
	for intf; do
		interfaces="$interfaces $intf"
	done
else
	flag="true"
	[ $remote -eq 0 ] && flag="false"
	cmclient -v interfaces GETO "Device.IP.Interface.[Enable=true].[X_ADB_Upstream=${flag}]"
	unset flag
fi
for interfaces in $interfaces; do
	help_lowlayer_ifname_get ifname "$interfaces"
	[ -z "$ifname" ] && continue
	cmclient -v addrs GETV "${interfaces}.IPv4Address.[Enable=true].IPAddress"
	for addrs in $addrs; do
		if [ "$remote" -eq 1 -a "$newX_ADB_AccessControlEnable" = "true" ]; then
			help_iptables -t nat -A NATSkip_Telnet${chainSuffix} -i ${ifname} -d ${addrs} -p tcp --dport ${newPort} -j NATSkip_TelnetRemote_ACL
		else
			help_iptables -t nat -A NATSkip_Telnet${chainSuffix} -i ${ifname} -d ${addrs} -p tcp --dport ${newPort} -j ACCEPT
		fi
		help_iptables -A Telnet${chainSuffix}In -i ${ifname} -d ${addrs} -j Telnet${chainSuffix}In_
		help_iptables -A Telnet${chainSuffix}Out -o ${ifname} -s ${addrs} -j Telnet${chainSuffix}Out_
		listen="$listen ${addrs}-${ifname}"
	done
	[ "$ipv6_global" = "true" ] || continue
	cmclient -v addrs GETV "${interfaces}.IPv6Address.[Enable=true].[IPAddressStatus=Preferred].IPAddress"
	for addrs in $addrs; do
		help_ip6tables -A Telnet${chainSuffix}In -i ${ifname} -d ${addrs} -j Telnet${chainSuffix}In_
		listen6="${listen6} $addrs"
	done
done
if [ "$newEnable" = "true" -a "$newX_ADB_AccessControlEnable" = "true" ]; then
	cmclient SET -u "${tmpiptablesprefix##*/}" "${obj}".X_ADB_ACLRule.[Enable=true].[Status=Disabled].Refresh true
fi
if [ "$newX_ADB_AccessControlEnable" = "true" ]; then
	help_iptables -R Telnet${chainSuffix}In_ 1 -s 0.0.0.1/32 -d 0.0.0.1/32 -j DROP
	help_ip6tables -R Telnet${chainSuffix}In_ 1 -s ::/128 -d ::/128 -j DROP
	help_ip6tables -R Telnet${chainSuffix}Out_ 1 -s ::/128 -d ::/128 -j DROP
else
	help_iptables_all -R Telnet${chainSuffix}In_ 1 -j ACCEPT
	help_iptables_all -R Telnet${chainSuffix}Out_ 1 -j ACCEPT
fi
cmclient -v login_banner GETV Device.UserInterface.X_ADB_LoginBanner
[ -n "$login_banner" ] && echo "$login_banner" >/tmp/telnet_login_banner || rm -f /tmp/telnet_login_banner
cmd_line="telnetd -i -u $gids -I $newSessionLifeTime"
[ -e /tmp/telnet_login_banner ] && cmd_line="$cmd_line -f /tmp/telnet_login_banner"
prefix="nointerrupt "
for listen in $listen; do
	echo "$prefix$listen,telnet,$newPort stream tcp nowait root /usr/sbin/telnetd ${cmd_line}"
done | { [ $remote -eq 1 ] && cat >$INETD_CONF_FILE_REMOTE || cat >$INETD_CONF_FILE_LOCAL; }
for listen6 in $listen6; do
	echo "nointerrupt $listen6,telnet,$newPort stream tcp6 nowait root /usr/sbin/telnetd ${cmd_line}"
done | { [ $remote -eq 1 ] && cat >>$INETD_CONF_FILE_REMOTE || cat >>$INETD_CONF_FILE_LOCAL; }
exit 0
