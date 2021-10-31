#!/bin/sh
AH_NAME="SSHAccessRules"
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_serialize.sh && help_serialize
case "$obj" in
Device.X_ADB_SSHServer.RemoteAccess.*)
chainSuffix="Remote"
;;
Device.X_ADB_SSHServer.LocalAccess.*)
chainSuffix="Local"
;;
esac
needRefresh() {
[ "$setRefresh" = "1" ] && return 0
help_is_changed Enable Type IPAddress SubnetMask IPAddressRangeMin IPAddressRangeMax IPv6Address && return 0
return 1
}
add_rule() {
[ "$oldType" = "IPv6Subnet" -a "$newType" != "IPv6Subnet" ] && delete_rule
[ "$oldType" != "IPv6Subnet" -a "$newType" = "IPv6Subnet" ] && delete_rule
case "$newType" in
Host)
if [ -n "$newIPAddress" ]; then
help_iptables -I "SSH${chainSuffix}In_" 2 -s "$newIPAddress" -j ACCEPT
help_iptables -I "SSH${chainSuffix}Out_" 2 -d "$newIPAddress" -j ACCEPT
[ "$chainSuffix" = "Remote" ] && help_iptables -t nat -I NATSkip_SSHRemote_ACL 1 -s "$newIPAddress" -j ACCEPT
fi
;;
Subnet)
if [ -n "$newIPAddress" -a -n "$newSubnetMask" ]; then
help_iptables -I "SSH${chainSuffix}In_" 2 -s "$newIPAddress"/"$newSubnetMask" -j ACCEPT
help_iptables -I "SSH${chainSuffix}Out_" 2 -d "$newIPAddress"/"$newSubnetMask" -j ACCEPT
[ "$chainSuffix" = "Remote" ] && help_iptables -t nat -I NATSkip_SSHRemote_ACL 1 -s "$newIPAddress"/"$newSubnetMask" -j ACCEPT
fi
;;
Range)
if [ -n "$newIPAddressRangeMin" -a -n "$newIPAddressRangeMax" ]; then
help_iptables -I "SSH${chainSuffix}In_" 2 -m iprange --src-range ${newIPAddressRangeMin}-${newIPAddressRangeMax} -j ACCEPT
help_iptables -I "SSH${chainSuffix}Out_" 2 -m iprange --dst-range ${newIPAddressRangeMin}-${newIPAddressRangeMax} -j ACCEPT
[ "$chainSuffix" = "Remote" ] && help_iptables -t nat -I NATSkip_SSHRemote_ACL 1 -m iprange --src-range ${newIPAddressRangeMin}-${newIPAddressRangeMax} -j ACCEPT
fi
;;
IPv6Subnet)
if [ -n "$newIPv6Address" ]; then
help_ip6tables -I "SSH${chainSuffix}In_" 2 -s ${newIPv6Address} -j ACCEPT
help_ip6tables -I "SSH${chainSuffix}Out_" 2 -d ${newIPv6Address} -j ACCEPT
fi
;;
esac
cmclient SET -u SSHAccessRules "${obj}.Status" Enabled
}
delete_rule() {
case "$oldType" in
Host)
if [ -n "$oldIPAddress" ]; then
help_iptables -D "SSH${chainSuffix}In_" -s "$oldIPAddress" -j ACCEPT
help_iptables -D "SSH${chainSuffix}Out_" -d "$oldIPAddress" -j ACCEPT
[ "$chainSuffix" = "Remote" ] && help_iptables -t nat -D NATSkip_SSHRemote_ACL -s "$oldIPAddress" -j ACCEPT
fi
;;
Subnet)
if [ -n "$oldIPAddress" -a -n "$oldSubnetMask" ]; then
help_iptables -D "SSH${chainSuffix}In_" -s "$oldIPAddress"/"$oldSubnetMask" -j ACCEPT
help_iptables -D "SSH${chainSuffix}Out_" -d "$oldIPAddress"/"$oldSubnetMask" -j ACCEPT
[ "$chainSuffix" = "Remote" ] && help_iptables -t nat -D NATSkip_SSHRemote_ACL -s "$oldIPAddress"/"$oldSubnetMask" -j ACCEPT
fi
;;
Range)
if [ -n "$oldIPAddressRangeMin" -a -n "$oldIPAddressRangeMax" ]; then
help_iptables -D "SSH${chainSuffix}In_" -m iprange --src-range ${oldIPAddressRangeMin}-${oldIPAddressRangeMax} -j ACCEPT
help_iptables -D "SSH${chainSuffix}Out_" -m iprange --dst-range ${oldIPAddressRangeMin}-${oldIPAddressRangeMax} -j ACCEPT
[ "$chainSuffix" = "Remote" ] && help_iptables -t nat -D NATSkip_SSHRemote_ACL -m iprange --src-range ${oldIPAddressRangeMin}-${oldIPAddressRangeMax} -j ACCEPT
fi
;;
IPv6Subnet)
if [ -n "$oldIPv6Address" ]; then
help_ip6tables -D "SSH${chainSuffix}In_" -s ${oldIPv6Address} -j ACCEPT
help_ip6tables -D "SSH${chainSuffix}Out_" -d ${oldIPv6Address} -j ACCEPT
fi
;;
esac
cmclient SET -u SSHAccessRules "${obj}.Status" Disabled
}
. /etc/ah/IPv6_helper_firewall.sh
. /etc/ah/helper_firewall.sh
case "$op" in
s)
if needRefresh; then
[ "$oldEnable" = "true" -a "$setRefresh" = "0" ] && delete_rule
[ "$newEnable" = "true" ] && add_rule
fi
;;
d)
[ "$oldEnable" = "true" -a "$oldStatus" != "Disabled" ] && delete_rule
;;
a)
[ "$newEnable" = "true" ] && add_rule
;;
esac
exit 0
