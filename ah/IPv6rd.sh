#!/bin/sh
AH_NAME="IPv6rd"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_functions.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/IPv6_helper_firewall.sh
address=''
ipv6rd_delegated_address=''
ipv6rd_enable=''
maskedaddress=''
ml=''
old_address=''
sixrd_spipv6prefix=''
sixrd_tun_ifname=''
LIFETIME_EXP=7200
TARGET="DROP"
ipv6_6rdrelay_antispoofing() {
if [ "$1" = "add" ]; then
help_ip6tables commit
help_ip6tables -D Basic -j Basic_$3
help_ip6tables -D BasicIn -j BasicIn_$3
help_ip6tables commit noerr
help_ip6tables -N Basic_$3
help_ip6tables -N BasicIn_$3
help_ip6tables -I Basic -j Basic_$3
help_ip6tables -I BasicIn -j BasicIn_$3
help_ip6tables -A Basic_$3 -o $3 ! -s $2 -j $TARGET
help_ip6tables -A Basic_$3 -i $3 -s $2 -j DROP
help_ip6tables -A BasicIn_$3 -i $4 -p ipv6-icmp --icmpv6-type 128/0 -s fe80::/64 -j ACCEPT
help_ip6tables -A BasicIn_$3 -i $4 -p ipv6-icmp --icmpv6-type 128/0 ! -s $2 -j DROP
else
help_ip6tables -F Basic_$3
help_ip6tables -F BasicIn_$3
help_ip6tables -D Basic -j Basic_$3
help_ip6tables -D BasicIn -j BasicIn_$3
help_ip6tables -X Basic_$3
help_ip6tables -X BasicIn_$3
fi
}
ipv6_basic_sanitation() {
if [ "$1" = "true" ]; then
help_ip6tables -A Basic -s ff00::/8 -j DROP
help_ip6tables -A BasicOut -s ff00::/8 -j DROP
help_ip6tables -A Basic -i 6rdtun+ -d ff01::/ff0f:: -j DROP # Interface-local scope
help_ip6tables -A Basic -o 6rdtun+ -d ff01::/ff0f:: -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d ff02::/ff0f:: -j DROP # Link-local scope
help_ip6tables -A Basic -o 6rdtun+ -d ff02::/ff0f:: -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d ff04::/ff0f:: -j DROP # Admin-local scope
help_ip6tables -A Basic -o 6rdtun+ -d ff04::/ff0f:: -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d ff05::/ff0f:: -j DROP # Site-local scope
help_ip6tables -A Basic -o 6rdtun+ -d ff05::/ff0f:: -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d ff08::/ff0f:: -j DROP # Organization-local scope
help_ip6tables -A Basic -o 6rdtun+ -d ff08::/ff0f:: -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -s fec0::/10 -j DROP # Site-local scope
help_ip6tables -A Basic -o 6rdtun+ -s fec0::/10 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d fec0::/10 -j DROP
help_ip6tables -A Basic -o 6rdtun+ -d fec0::/10 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -s ::ffff:0:0/96 -j DROP # IPv4-Mapped Addresses
help_ip6tables -A Basic -o 6rdtun+ -s ::ffff:0:0/96 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d ::ffff:0:0/96 -j DROP
help_ip6tables -A Basic -o 6rdtun+ -d ::ffff:0:0/96 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -s ::/96 -j DROP # IPv4-Compatible Addresses
help_ip6tables -A Basic -o 6rdtun+ -s ::/96 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d ::/96 -j DROP
help_ip6tables -A Basic -o 6rdtun+ -d ::/96 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -s 2001:db8::/32 -j DROP # Documentation Prefix
help_ip6tables -A Basic -o 6rdtun+ -s 2001:db8::/32 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d 2001:db8::/32 -j DROP
help_ip6tables -A Basic -o 6rdtun+ -d 2001:db8::/32 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -s 2001:10::/28 -j DROP # ORCHID
help_ip6tables -A Basic -o 6rdtun+ -s 2001:10::/28 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d 2001:10::/28 -j DROP
help_ip6tables -A Basic -o 6rdtun+ -d 2001:10::/28 -j $TARGET
help_ip6tables -A Basic -m rt --rt-type 0 -j DROP
help_ip6tables -A BasicOut -m rt --rt-type 0 -j DROP
help_ip6tables -A Basic -i 6rdtun+ -s fc00::/7 -j DROP
help_ip6tables -A Basic -o 6rdtun+ -s fc00::/7 -j $TARGET
help_ip6tables -A Basic -i 6rdtun+ -d fc00::/7 -j DROP
help_ip6tables -A Basic -o 6rdtun+ -d fc00::/7 -j $TARGET
help_ip6tables -A BasicIn -i 6rdtun+ -p udp --dport 53 -j DROP
help_ip6tables -A BasicIn -i 6rdtun+ -p tcp --dport 53 -j DROP # For zone transfer
help_ip6tables -A BasicIn -i 6rdtun+ -p udp --dport 547 -j DROP
else
help_ip6tables -F Basic
help_ip6tables -F BasicIn
help_ip6tables -F BasicOut
fi
}
service_read () {
local something_changed=0 lowerlayers
cmclient -v ipv6rd_enable GETV "Device.IPv6rd.Enable"
for i in AddressSource AllTrafficToBorderRelay BorderRelayIPv4Addresses IPv4MaskLength SPIPv6Prefix \
TunnelInterface TunneledInterface; do
if eval [ \${changed${i}:=0} -eq 1 ]; then
something_changed=1
break;
fi
done
[ $something_changed -eq 0 -a $setEnable -eq 0 -a $setAddressSource -eq 0 ] && exit 0
[ "$changedBorderRelayIPv4Addresses" = "1" -a ${#oldBorderRelayIPv4Addresses} -ne 0 ] && \
sixrd_oldborderrelayipv4address="$oldBorderRelayIPv4Addresses"
sixrd_preflen="${newSPIPv6Prefix#*/}"
sixrd_spipv6prefix=`ipv6_short_format "${newSPIPv6Prefix%/*}"`
sixrd_spipv6prefix="${sixrd_spipv6prefix}/${sixrd_preflen}"
if [ "$changedSPIPv6Prefix" = "1" -a ${#oldSPIPv6Prefix} -ne 0 ]; then
sixrd_oldlen="${oldSPIPv6Prefix#*/}"
sixrd_oldspipv6prefix=`ipv6_short_format "${oldSPIPv6Prefix%/*}"`
sixrd_oldspipv6prefix="${sixrd_oldspipv6prefix}/${sixrd_oldlen}"
fi
if [ ${#newAddressSource} -ne 0 ]; then
cmclient -v address GETV "$newAddressSource.IPAddress"
[ ${#address} -eq 0 ] && return
if [ ${#newIPv4MaskLength} -ne 0 ]; then
ml=`expr 32 - $newIPv4MaskLength`
maskedaddress=`ipv6_from_ipv4_mask_to_prefix_part $address $ml`
fi
else
return
fi
[ "$changedAddressSource" = "1" -a ${#oldAddressSource} -ne 0 ] && \
cmclient -v old_address GETV "$oldAddressSource.IPAddress"
[ "$changedIPv4MaskLength" = "1" -a ${#oldIPv4MaskLength} -ne 0 ] && old_ml=`expr 32 - $oldIPv4MaskLength`
if [ ${#old_address} -ne 0 -a ${#old_ml} -eq 0 ]; then
old_maskedaddress=`ipv6_from_ipv4_mask_to_prefix_part $old_address $ml`
elif [ ${#old_ml} -ne 0 -a ${#old_address} -eq 0 ]; then
old_maskedaddress=`ipv6_from_ipv4_mask_to_prefix_part $address $old_ml`
elif [ ${#old_address} -ne 0 -a ${#old_ml} -ne 0 ]; then
old_maskedaddress=`ipv6_from_ipv4_mask_to_prefix_part $old_address $old_ml`
fi
[ "$changedAllTrafficToBorderRelay" = "1" -a ${#oldAllTrafficToBorderRelay} -ne 0 ] && old_traffic="$oldAllTrafficToBorderRelay"
cmclient -v lowerlayers GETV $newTunnelInterface.LowerLayers
cmclient -v sixrd_tun_ifname GETV $lowerlayers.Name
if [ "$changedTunnelInterface" = "1" -a ${#oldTunnelInterface} -ne 0 ]; then
cmclient -v old_lowerlayers GETV $oldTunnelInterface.LowerLayers
cmclient -v old_tun_name GETV $old_lowerlayers.Name
fi
sixrd_tunneledinterface="$newTunneledInterface"
[ "$changedTunneledInterface" = "1" -a ${#oldTunneledInterface} -ne 0 ] && sixrd_oldtunneledinterface="$oldTunneledInterface"
}
help_6rd_compute_prefix() {
local prefix="$1" maskaddr="$2" itf="$3" output_val="$4" output_generic="$5" prefix_len maskaddr_len prefix_tmp maskaddr_tmp len additional_len
prefix_len="${prefix#*/}"
prefix_tmp="${prefix%%\::*}"
prefix_tmp=$(help_ipv6_expand $prefix_tmp)
prefix_tmp=`echo $prefix_tmp | sed 's/://g'`
prefix_tmp=`ipv6_hex_to_bin $prefix_tmp ${#prefix_tmp}`
prefix_tmp=`ipv6_bin_to_hex $prefix_tmp $prefix_len`
maskaddr_tmp=`echo $maskaddr | sed 's/://g'`
maskaddr_len=$((${#maskaddr_tmp} * 4))
len=$((maskaddr_len + prefix_len))
additional_len=$((64 - len))
prefix_tmp=$prefix_tmp$maskaddr_tmp"0000000000000000"
prefix_tmp=${prefix_tmp:0:16}
prefix_tmp=`echo $prefix_tmp | sed "s/..../&:/g"`
prefix_tmp=`echo $prefix_tmp | sed "s/:$//"`
if [ ${#output_generic} -ne 0 ]; then
eval $output_generic='$prefix_tmp::/$len'
fi
[ ${#output_val} -ne 0 ] && eval $output_val='$prefix_tmp'
}
help_ipv6_clean_old () {
local old_del_prefix="$1" old_address="$2" old_name="$3"
[ ${#old_del_prefix} -eq 0 ] && old_del_prefix="$ipv6rd_delegated_address"
[ ${#old_address} -eq 0 ] && old_address="$address"
[ ${#old_name} -eq 0 ] && old_name="$sixrd_tun_ifname"
echo "### $AH_NAME: <ip -6 addr del $old_del_prefix dev $old_name> ###" >> /dev/console
ip -6 addr del "$old_del_prefix" dev "$old_name"
echo "### $AH_NAME: <ip tunnel del $tunname mode sit local $old_address ttl 64> ###" > /dev/console
ip tunnel del "$tunname" mode sit local "$old_address" ttl 64
}
service_reconf_6rd () {
local to_delete="$1" tunname='' oldtunname='' old sixrd_cmd ipv6rd_prefix ipv6rd_delegated_prefix ipv6_prefix_obj ipv6_address_obj obj_id \
itf ipv6_oldprefix_obj prefix ipv6rd_pfx mtu ipv6rd_prefix_generic
[ "$newEnable" = "true" -a "$ipv6rd_enable" = "true" -a ${#to_delete} -eq 0 ] && sixrd_cmd="add" || sixrd_cmd="del"
if [ ${#address} -ne 0 -a ${#maskedaddress} -ne 0 -a ${#newBorderRelayIPv4Addresses} -ne 0 -a ${#sixrd_spipv6prefix} -ne 0 -a \
${#sixrd_tun_ifname} -ne 0 ]; then
help_6rd_compute_prefix "$sixrd_spipv6prefix" "$maskedaddress" "$newTunnelInterface" "ipv6rd_prefix" "ipv6rd_prefix_generic"
ipv6rd_delegated_address="${ipv6rd_prefix}::1/64"
ipv6rd_delegated_prefix="`ipv6_short_format "${ipv6rd_prefix}::"`/64"
cmclient -v ipv6_prefix_obj GETO "$newTunnelInterface.IPv6Prefix.[Prefix=$ipv6rd_delegated_prefix]"
cmclient -v ipv6_address_obj GETO "$newTunnelInterface.IPv6Address.[Prefix=$ipv6_prefix_obj]"
if [ ${#sixrd_oldspipv6prefix} -ne 0 -a ${#old_maskedaddress} -ne 0 ]; then
help_6rd_compute_prefix "$sixrd_oldspipv6prefix" "$old_maskedaddress" "$newTunnelInterface" "ipv6rd_oldprefix" ""
elif [ ${#sixrd_oldspipv6prefix} -eq 0 -a ${#old_maskedaddress} -ne 0 ]; then
help_6rd_compute_prefix "$sixrd_spipv6prefix" "$old_maskedaddress" "$newTunnelInterface" "ipv6rd_oldprefix" ""
elif [ ${#sixrd_oldspipv6prefix} -ne 0 -a ${#old_maskedaddress} -eq 0 ]; then
help_6rd_compute_prefix "$sixrd_oldspipv6prefix" "$maskedaddress" "$newTunnelInterface" "ipv6rd_oldprefix" ""
fi
if [ ${#ipv6rd_oldprefix} -ne 0 ]; then
ipv6rd_old_del_prefix="`ipv6_short_format "${ipv6rd_oldprefix}::"`/64"
ipv6rd_old_del_address="${ipv6rd_oldprefix}::1/64"
fi
[ ${#newTunneledInterface} -ne 0 ] && \
tunname="${newTunneledInterface#Device.IP.Interface.}" && tunname="6rdtun$tunname"
cmclient -v ipv6rd_obj GETO "Device.IPv6rd.InterfaceSetting.[TunneledInterface=$newTunneledInterface]"
for ipv6rd_obj in $ipv6rd_obj; do
cmclient -v tmp GETV "$ipv6rd_obj.TunnelInterface"
[ ${#tmp} -ne 0 ] && cmclient -v tmp GETV "$tmp.LowerLayers"
[ ${#tmp} -ne 0 ] && cmclient -v tmp GETV "$tmp.Name"
lan_dev="${lan_dev:+$lan_dev,}$tmp"
done
if [ "$changedTunneledInterface" -eq 1 -a ${#oldTunneledInterface} -ne 0 ]; then
cmclient -v ipv6rd_obj GETO "Device.IPv6rd.InterfaceSetting.[TunneledInterface=$oldTunneledInterface].[Enable=true]"
for ipv6rd_obj in $ipv6rd_obj; do
[ "$ipv6rd_obj" != "$obj" ] && cmclient SET "$ipv6rd_obj.Enable" "true" && break;
done
if [ ${#ipv6rd_obj} -eq 0 ]; then
oldtunname="${oldTunneledInterface#Device.IP.Interface.}"
oldtunname="6rdtun$oldtunname"
[ ${#old_address} -eq 0 ] && old="$address" || old="$old_address"
echo "### $AH_NAME: <ip tunnel del $oldtunname mode sit local $old ttl 64> ###" >> /dev/console
ip tunnel del "$oldtunname" mode sit local "$old" ttl 64
fi
fi
if [ ${#ipv6rd_old_del_address} -ne 0 -o ${#old_address} -ne 0 -o ${#sixrd_oldborderrelayipv4address} -ne 0 -o \
${#old_traffic} -ne 0 -o ${#old_tun_name} -ne 0 ]; then
if [ ${#ipv6rd_old_del_prefix} -ne 0 ]; then
cmclient -v ipv6_oldprefix_obj GETO "$newTunnelInterface.IPv6Prefix.[Prefix=$ipv6rd_old_del_prefix]"
[ ${#ipv6_oldprefix_obj} -ne 0 ] && cmclient -u "IPIfIPv6${ipv6_oldprefix_obj}" DEL "$ipv6_oldprefix_obj"
fi
help_ipv6_clean_old "$ipv6rd_old_del_address" "$old_address" "$old_tun_name"
fi
if [ "$sixrd_cmd" = "add" ]; then
[ ${#ipv6_prefix_obj} -ne 0 ] && cmclient -u "IPIfIPv6${ipv6_prefix_obj}" DEL "$ipv6_prefix_obj"
ip -6 addr del "$ipv6rd_delegated_address" dev "$sixrd_tun_ifname"
echo "### $AH_NAME: <ip -6 addr add $ipv6rd_delegated_address dev $sixrd_tun_ifname> ###" > /dev/console
ip -6 addr add "$ipv6rd_delegated_address" dev "$sixrd_tun_ifname"
else
if [ ${#ipv6rd_old_del_prefix} -eq 0 ]; then
cmclient -v itf GETO "$newTunnelInterface"
cmclient -v prefix GETV $itf.IPv6Prefix.[Origin=AutoConfigured].[Prefix!$ipv6rd_delegated_prefix].Prefix
for prefix in $prefix; do
case $prefix in
fec0:0:0:ffff::* ) ;;
* ) ipv6rd_old_del_prefix="$ipv6rd_old_del_prefix $prefix" ;;
esac
done
fi
[ "$to_delete" = "invalid" -a ${#ipv6_prefix_obj} -ne 0 ] && cmclient -u "IPIfIPv6${ipv6_prefix_obj}" DEL "$ipv6_prefix_obj"
for ipv6rd_pfx in $ipv6rd_old_del_prefix; do
echo "### $AH_NAME: <ip -6 addr del ${ipv6rd_pfx%/*}1/64 dev $sixrd_tun_ifname> ###" > /dev/console
ip -6 addr del ${ipv6rd_pfx%/*}1/64 dev "$sixrd_tun_ifname"
done
if [ "$to_delete" = "invalid" ]; then
for ipv6rd_pfx in $ipv6rd_old_del_prefix; do
echo "### $AH_NAME: <ip -6 addr add $ipv6rd_pfx dev $sixrd_tun_ifname preferred_lft 0 valid_lft $LIFETIME_EXP> ###" > /dev/console
ip -6 addr add "$ipv6rd_pfx" dev "$sixrd_tun_ifname" preferred_lft 0 valid_lft $LIFETIME_EXP
done
fi
fi
echo "### $AH_NAME: <ip tunnel $sixrd_cmd $tunname mode sit local $address ttl 64> ###" > /dev/console
ip tunnel "$sixrd_cmd" "$tunname" mode sit local "$address" ttl 64
[ "$sixrd_cmd" = "add" ] && ipv6_proc_enable "true" "$tunname"
ipv6_6rdrelay_antispoofing "$sixrd_cmd" "$ipv6rd_prefix_generic" "$tunname" "$lan_dev"
if [ "$sixrd_cmd" = "add" ] ; then
echo "### $AH_NAME: <ip tunnel 6rd dev $tunname 6rd-prefix $sixrd_spipv6prefix> ###" > /dev/console
ip tunnel 6rd dev $tunname 6rd-prefix $sixrd_spipv6prefix
ip link set $tunname up
echo "### $AH_NAME: <ip route $sixrd_cmd ::/0  via ::$newBorderRelayIPv4Addresses dev $tunname> ###" > /dev/console
ip route $sixrd_cmd ::/0  via ::$newBorderRelayIPv4Addresses dev $tunname
if [ "$newAllTrafficToBorderRelay" = "false" ] ; then
echo "### $AH_NAME: <ip -6 addr add ${ipv6rd_prefix}::/${sixrd_preflen} dev $tunname> ###" >> /dev/console
ip -6 addr add "${ipv6rd_prefix}::/${sixrd_preflen}" dev "$tunname"
fi
cmclient SETE "$obj.Status" "Enabled"
else
cmclient SETE "$obj.Status" "Disabled"
fi
else
[ ${#to_delete} -ne 0 ] && cmclient SETE "$obj.Status" "Disabled" || cmclient SETE "$obj.Status" "Error"
fi
}
service_delete() {
service_read
service_reconf_6rd "true"
}
service_config () {
local object dev_name sixrd_obj obj_id ipv4_arg
case "$obj" in
*"X_ADB_Stats"* )
if [ "$setX_ADB_Reset" = "1" ]; then
object="${obj%%.X_ADB_Stats}"
object="${object##*IPv6rd.InterfaceSetting.}"
dev_name=6rdtun$object
ioctl -i "$dev_name" -n 0x89fc -a null > /dev/null
fi
;;
"Device.IPv6rd")
if [ "$changedEnable" -eq 1 ] ; then
ipv6_basic_sanitation $newEnable
rm /tmp/cfg/cache/ip6tables
cmclient -u "$AH_NAME" SET "$obj.InterfaceSetting.[Enable=true].Enable" "true"
fi
;;
"Device.IPv6rd.InterfaceSetting"* )
service_read
if [ "$changedEnable" -eq 1 -o "$newEnable" = "true" ] && \
[ "$ipv6rd_enable" = "true" -o "$user" = "$AH_NAME" -o "$user" = "Time" -o "$user" = "CWMP" ]; then
case "$user" in
"IPIfIPv4"*)
ipv4_arg="${user#IPIfIPv4}"
case "$ipv4_arg" in
"add" ) service_reconf_6rd ;;
"del" ) service_reconf_6rd "invalid" ;;
"del"* )
ipv4_arg="${ipv4_arg#del}"
address="$ipv4_arg"
if [ ${#maskedaddress} -ne 0 ]; then
maskedaddress=`ipv6_from_ipv4_mask_to_prefix_part $address $ml`
service_reconf_6rd "invalid"
fi
;;
* )
address="$ipv4_arg"
if [ ${#maskedaddress} -ne 0 ]; then
maskedaddress=`ipv6_from_ipv4_mask_to_prefix_part $address $ml`
service_reconf_6rd "true"
fi
;;
esac
;;
*)	service_reconf_6rd
;;
esac
fi
;;
esac
}
service_get () {
local object="$1" param="$2" dev_name
case $object in
*"X_ADB_Stats" )
object="${object%%.X_ADB_Stats}"
object="${object##*IPv6rd.InterfaceSetting.}"
dev_name=6rdtun$object
if [ ${#dev_name} -ne 0 ]; then
help_get_base_stats "$param" "$dev_name"
else
echo ""
fi
;;
esac
}
if [ "$1" = "init" ]; then
cmclient -v ipv6rd_enable GETV "Device.IPv6rd.Enable"
[ "$ipv6rd_enable" = "true" ] && ipv6_basic_sanitation "true"
exit 0
fi
case "$op" in
s)
service_config
;;
d)
service_delete
;;
g)
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
;;
esac
exit 0
