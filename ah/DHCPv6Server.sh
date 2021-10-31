#!/bin/sh
AH_NAME="DHCPv6Server"
[ "$user" = "$AH_NAME" ] && exit 0
[ "$user" = "eh_ipv6" -a "$1" != "ifchange" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize "$AH_NAME"
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/helper_svc.sh
. /etc/ah/IPv6_helper_firewall.sh
dhcp6s_conf="/tmp/dhcp6s.conf"
dhcp6s_leases="/tmp/dhcp6s.leases"
print_pool_client_ipv6address ()
{
local client="$2" sa="$3" clientDUID="$4" recT="$5" \
ipv6address addr preferredTR validTR retval="" iaid
cmclient -v ipv6address GETO $client.IPv6Address
for ipv6address in $ipv6address; do
cmclient -v addr GETV "${ipv6address}.IPAddress"
cmclient -v iaid GETV "${ipv6address}.X_ADB_IAID"
cmclient -v preferredTR GETV \
"${ipv6address}.X_ADB_PreferredTimeRemaining"
cmclient -v validTR GETV \
"${ipv6address}.X_ADB_ValidTimeRemaining"
[ "$preferredTR" = "-1" ] && preferredTR="infinity"
[ "$validTR" = "-1" ] && validTR="infinity"
retval="${retval}Client $sa,$clientDUID,$iaid,$recT\n"
retval="${retval}	IPv6Address $addr,$preferredTR,$validTR\n"
done
eval $1='"$retval"'
}
print_pool_client_ipv6prefix ()
{
local client="$2" sa="$3" clientDUID="$4" recT="$5" \
ipv6prefix prefx preferredTR validTR retval="" iaid
cmclient -v ipv6prefix GETO $client.IPv6Prefix
for ipv6prefix in $ipv6prefix; do
cmclient -v prefx GETV "${ipv6prefix}.Prefix"
cmclient -v iaid GETV "${ipv6prefix}.X_ADB_IAID"
cmclient -v preferredTR GETV \
"${ipv6prefix}.X_ADB_PreferredTimeRemaining"
cmclient -v validTR GETV "${ipv6prefix}.X_ADB_ValidTimeRemaining"
[ "$preferredTR" = "-1" ] && preferredTR="infinity"
[ "$validTR" = "-1" ] && validTR="infinity"
retval="${retval}Client $sa,$clientDUID,$iaid,$recT\n"
retval="${retval}	IPv6Prefix $prefx,$preferredTR,$validTR\n"
done
eval $1='"$retval"'
}
print_pool_client ()
{
local pool="$2" client sa clientDUID address prefix recT retval=""
cmclient -v client GETO $pool.Client
for client in $client; do
cmclient -v sa GETV "${client}.SourceAddress"
cmclient -v clientDUID GETV "${client}.X_ADB_ClientDUID"
cmclient -v recT GETV "${client}.X_ADB_RecordedTime"
print_pool_client_ipv6address address "$client" "$sa" "$clientDUID" "$recT"
print_pool_client_ipv6prefix prefix "$client" "$sa" "$clientDUID" "$recT"
[ ${#address} -ne 0 ] && retval="${retval}${address}"
[ ${#prefix} -ne 0 ] && retval="${retval}${prefix}"
done
eval $1='"$retval"'
}
fromtr181lifetime ()
{
if islifetimeinfinity "$1"; then
echo "infinity"
else
local _curr_sec=`date -u +"%s"`
_lt=`help_ipv6_lft_to_secs "$1" "$_curr_sec"`
[ "${_lt}" -gt 0 ] && echo "${_lt}" || echo "expired"
fi
}
num_bits() {
local nbr=$2 maxintbit shift=1 count=0
maxintbit=$((nbr-1))
[ $nbr -eq 1 ] && eval $1='1' && return 0
while [ $shift -le $maxintbit ]; do
shift=$((shift<<1))
count=$((count+1))
done
eval $1='$count'
return 0
}
get_pd_base_for_pool() {
local pool=$3 prefix=$2 count=0 bits=0 length poolsiapd tmp \
save_local_ifs this_pool_idx=0
save_local_ifs="$IFS"
IFS="$save_IFS"
cmclient -v poolsiapd GETO Device.DHCPv6.Server.Pool.[IAPDEnable=true]
for tmp in $poolsiapd; do
[ "$tmp" = "$pool" ] && this_pool_idx=$count
count=$((count+1))
done
num_bits 'bits' $count
length=${prefix#*/}
prefix=${prefix%/*}
prefix=$(help_create_child_prefix "$prefix" "$length" "$this_pool_idx" "$bits")
eval  $1='$prefix'
IFS="$save_local_ifs"
return 0
}
print_prefixes ()
{
local pfx="$1" pfx_type="$2" pool="$3" save_IFS _enable _status \
pfxval preferred valid origin
[ -n "${IFS+x}" ] && save_IFS="$IFS" || unset save_IFS
IFS=","
cmclient -v pfx GETV $1
for pfx in $pfx; do
cmclient -v _enable GETV "${pfx}.Enable"
cmclient -v _status GETV "${pfx}.Status"
if [ "$_enable" != "true" -o "$_status" != "Enabled" ]; then
continue
fi
cmclient -v pfxval GETV "${pfx}.Prefix"
[ "$pfx_type" = "IAPDPrefix" ] && \
get_pd_base_for_pool 'pfxval' "$pfxval" "$pool"
cmclient -v preferred GETV "${pfx}.PreferredLifetime"
preferred="$(fromtr181lifetime $preferred)"
if [ "$preferred" != "expired" ]; then
cmclient -v valid GETV "${pfx}.ValidLifetime"
valid="$(fromtr181lifetime $valid)"
echo "$pfx_type ${pfxval},${preferred},${valid}"
fi
done
[ -n "${save_IFS+x}" ] && IFS="$save_IFS" || unset IFS
}
print_pool_assoc_criterion ()
{
local pool="$1" var="$2" val
cmclient -v val GETV "${pool}.${var}"
if [ -n "${val}" ]; then
echo "${var} ${val}"
cmclient -v val GETV "${pool}.${var}Exclude"
if [ "$val" = "true" ]; then
echo "${var}Exclude yes"
fi
fi
}
print_pool_options ()
{
local pool="$1" opt Tag Value Type passthrough_client refopts \
enableDNSPT
cmclient -v opt GETO "$pool.Option.*.[Enable=true]"
for opt in $opt; do
cmclient -v Tag GETV "${opt}.Tag"
cmclient -v Value GETV "${opt}.Value"
cmclient -v Type GETV "${opt}.X_ADB_Type"
cmclient -v passthrough_client GETV "${opt}.PassthroughClient"
if [ -n "$passthrough_client" ]; then
cmclient -v refopts GETO \
"${passthrough_client}.ReceivedOption.*.[Tag=$Tag]"
if [ -n "$refopts" ]; then
set -f
set -- $refopts
local refopt="$1"
set +f
cmclient -v Value GETV "${refopt}.Value"
Type="Hex"
fi
fi
if [ "$Tag" = "23" ]; then
cmclient -v enableDNSPT GETV \
"${pool}.X_ADB_EnableDNSPassthrough"
[ "$enableDNSPT" = "true" ] && continue;
fi
if [ -z "$Tag" -o -z "$Type" ] || \
[ "$Type" != "Empty" -a -z "$Value" ]; then
continue;
fi
echo "Option ${Tag};${Type};${Value}"
done
}
maybe_set_dns_passthrough()
{
local pool="$1" enableDNSPT iface dns ipa
cmclient -v enableDNSPT GETV "${pool}.X_ADB_EnableDNSPassthrough"
[ "$enableDNSPT" = "true" ] || return 0
cmclient -v iface GETV "${pool}.Interface"
cmclient -v ipa GETV "${iface}.IPv6Address.*.IPAddress"
for ipa in $ipa; do
case $ipa in
fe80::*)
dns="$ipa"
break
;;
esac
done
if [ -n "$dns" ]; then
echo "Option 23;IPv6AddressList;${dns}"
fi
}
print_pool_config ()
{
local pool="$1" mode="Stateless" var val ifname order clients
cmclient -v ifname GETV ${pool}.Interface
help_lowlayer_ifname_get ifname "$ifname"
[ -z "$ifname" ] && return 1
echo "Pool ${pool#Device.DHCPv6.Server.Pool.}"
echo "Interface ${ifname}"
cmclient -v order GETV ${pool}.Order
echo "Order $order"
for var in DUID UserClassID VendorClassID SourceAddress; do
print_pool_assoc_criterion "${pool}" "${var}"
done
cmclient -v val GETV "${pool}.SourceAddressMask"
[ -n "$val" ] && echo "SourceAddressMask ${val}"
for var in IANA IAPD; do
cmclient -v val GETV "$pool.${var}Enable"
echo "${var}Enable $val"
if [ "$val" = "true" ]; then
print_prefixes "$pool.${var}Prefixes" "${var}Prefix" \
"$pool"
mode="Stateful"
fi
done
cmclient -v val GETV "${pool}.IAPDEnable"
if [ "$val" = "true" ]; then
cmclient -v val GETV "${pool}.IAPDAddLength"
local bits=0 count=0 poolsiapd
cmclient -v poolsiapd GETO \
Device.DHCPv6.Server.Pool.[IAPDEnable=true]
for poolsiapd in $poolsiapd; do
count=$((count+1))
done
if [ $count -gt 0 ]; then
num_bits 'bits' $count
[ $bits -lt $val ] && val=$(($val-bits))
fi
[ ${#val} -ne 0 ] && echo "IAPDAddLength ${val}"
fi
echo "Mode ${mode}"
print_pool_options "$pool"
maybe_set_dns_passthrough "$pool"
return 0
}
print_pool_leases ()
{
local pool="$1" mode="Stateless" clients
print_pool_client clients "$pool"
printf '%b' "$clients"
return 0
}
make_dhcp6s_config ()
{
local duid have_any_pools pool interfaces policy \
stage="`mktemp -t dhcp6d.conf.XXXXXX`"
help_ip6tables -F DHCPServicesPoolOut
help_ip6tables -F DHCPServicesPoolIn
cmclient -v duid GETV Device.DHCPv6.Server.X_ADB_DUID
echo "server_duid ${duid:-NULL}" > $stage
cmclient -v policy GETV Device.DHCPv6.Server.X_ADB_AcceptSolicityPolicy
echo "AcceptSolicityPolicy $policy" >> $stage
cmclient -v pool GETO Device.DHCPv6.Server.Pool.*.[Enable=true]
for pool in $pool; do
[ "$op" = "d" -a "$pool" = "$obj" ] && continue
cmclient -v ifname GETV ${pool}.Interface
help_lowlayer_ifname_get ifname "$ifname"
if [ -z "$ifname" ]; then
cmclient SET -u "$AH_NAME" "${pool}.Status" \
"Error_Misconfigured" > /dev/null
continue
fi
if help_item_add_uniq_in_list interfaces "$interfaces" \
"$ifname"; then
help_ip6tables -A DHCPServicesPoolOut -o $ifname \
-p udp --dport 546 -j ACCEPT
help_ip6tables -A DHCPServicesPoolIn -i $ifname \
-p udp --dport 547 -j ACCEPT
fi
if ! print_pool_config "$pool"; then
cmclient SET -u "$AH_NAME" "${pool}.Status" \
"Error_Misconfigured" > /dev/null
else
cmclient SET -u "$AH_NAME" "${pool}.Status" Enabled \
> /dev/null
have_any_pools="yes"
fi
done >> $stage
if [ -z "$have_any_pools" ]; then
rm -f $stage
return 1
fi
mv $stage ${dhcp6s_conf}
}
create_pool_leases_file ()
{
[ ${#1} -eq 0 ] && return 1
local pool="$1" lease_file=""
lease_file="${dhcp6s_leases}.${pool#Device.DHCPv6.Server.Pool.}"
[ -f ${lease_file} ] && rm -f ${lease_file}
print_pool_leases "$pool" > ${lease_file}
}
make_dhcp6s_leases ()
{
local pool=""
cmclient -v pool GETO Device.DHCPv6.Server.Pool.*.[Enable=true]
for pool in $pool; do
rm -f ${dhcp6s_leases}.${pool#Device.DHCPv6.Server.Pool.}
[ "$op" = "d" -a "$pool" = "$obj" ] && continue
create_pool_leases_file ${pool}
done
}
restart_dhcp6s ()
{
[ "$dhcpd_enable" = "true" -a "$ipv6_enable" = "true" ] || return
local valid_conf=1
if ! make_dhcp6s_config; then
valid_conf=0
fi
if [ $valid_conf -eq 0 ]; then
help_svc_stop dhcp6s "" 15
return 1
fi
make_dhcp6s_leases
if ! killall -SIGUSR2 dhcp6s; then
help_svc_start "/bin/dhcp6s -c ${dhcp6s_conf}" 'dhcp6s' \
'' '' '' '15'
fi
}
stop_dhcp6s ()
{
help_ip6tables -F DHCPServicesPoolOut
help_ip6tables -F DHCPServicesPoolIn
help_svc_stop dhcp6s "" 15
}
validate_ianaprefix() {
local _prefix=$1 _status="" origin="" prefixval=""
cmclient -v _status GETV "$_prefix".PrefixStatus
[ "$_status" = "Invalid" ] && return 1
cmclient -v origin GETV "$_prefix".Origin
if [ "$origin" = "Child" -o "$origin" = "AutoConfigured" ]; then
cmclient -v prefixval GETV "$_prefix".Prefix
case "$prefixval" in
fe80::*)
;;
fec0:*)
;;
*)
return 0
;;
esac
fi
return 1
}
validate_iapdprefix() {
local _prefix="$1" _status origin prefixval
cmclient -v _status GETV "$_prefix".PrefixStatus
[ "$_status" = "Invalid" ] && return 1
cmclient -v origin GETV "$_prefix".Origin
if [ "$origin" = "PrefixDelegation" -o \
"$origin" = "AutoConfigured" ] || \
[ "$origin" = "Child" -o "$origin" = "AutoConfigured" ]; then
cmclient -v prefixval GETV "$_prefix".Prefix
case "$prefixval" in
fe80::*)
;;
fec0:*)
;;
*)
return 0
;;
esac
fi
return 1
}
align_ianaprefixes() {
local _enable=$1 _ianaenable=$2 _ianamanualprefixes=$3 _interface=$4 \
_pool_obj="${5:-${obj}}" ianaprefixes origin prefix
if [ "$_enable" = "true" -a "$_ianaenable" = "true" ]; then
ianaprefixes=$_ianamanualprefixes
cmclient -v prefix GETO "$_interface".IPv6Prefix
for prefix in $prefix; do
validate_ianaprefix "$prefix" && \
ianaprefixes="${ianaprefixes:+$ianaprefixes,}$prefix"
done
fi
cmclient SET -u "$AH_NAME" "$_pool_obj".IANAPrefixes "$ianaprefixes"
}
align_iapdprefixes() {
local _enable="$1" _iapdenable="$2" _iapdmanualprefixes="$3" \
_interface="$4" _pool_obj="${5:-${obj}}" iapdprefixes \
prefixlist prefix
if [ "$_enable" = "true" -a "$_iapdenable" = "true" ]; then
iapdprefixes=$_iapdmanualprefixes
cmclient -v prefixlist GETO "$_interface".IPv6Prefix
for prefix in $prefixlist; do
validate_iapdprefix "$prefix" && \
iapdprefixes="${iapdprefixes:+$iapdprefixes,}$prefix"
done
fi
cmclient SETE "$_pool_obj".IAPDPrefixes "$iapdprefixes"
}
service_add() {
case "$obj" in
Device.DHCPv6.Server.Pool.*.Option.*)
;;
Device.DHCPv6.Server.Pool.*)
local id maxorder=0
cmclient -v id GETV "Device.DHCPv6.Server.Pool.*.Order"
for id in $id; do
[ $id -gt $maxorder ] && maxorder=$id
done
maxorder=$((maxorder + 1))
cmclient SET -u "$AH_NAME" "$obj".Order $maxorder
;;
esac
}
service_delete() {
case "$obj" in
Device.DHCPv6.Server.Pool.*.Option.*)
;;
Device.DHCPv6.Server.Pool.*)
local id
cmclient -v id GETO \
"Device.DHCPv6.Server.Pool.*.[Order+$oldOrder]"
for id in $id; do
cmclient -v order GETV "$id".Order
cmclient SET -u "$AH_NAME" "$id.Order" \
"$((order - 1))"
done
;;
esac
restart_dhcp6s
}
init_iana_prefixes() {
local pool ifobj prefix
cmclient -v pool GETO \
Device.DHCPv6.Server.Pool.*.[Enable=true].[IANAEnable=true]
for pool in $pool; do
cmclient -v ifobj GETV "$pool.Interface"
cmclient -v prefix GETV $pool.IANAManualPrefixes
align_ianaprefixes "true" "true" "$prefix" "$ifobj" "$pool"
done
}
init_iapd_prefixes() {
local ifobj pool iapdprefixes
cmclient -v pool GETO \
Device.DHCPv6.Server.Pool.*.[Enable=true].[IAPDEnable=true]
for pool in $pool; do
cmclient -v ifobj GETV $pool.Interface
cmclient -v iapdprefixes GETV $pool.IAPDManualPrefixes
align_iapdprefixes "true" "true" "$iapdprefixes" "$ifobj" "$pool"
done
}
service_config() {
case "$obj" in
Device.DHCPv6.Server)
if [ "$newEnable" = "true" -a \
"$ipv6_enable" = "true" ]; then
if [ $changedEnable -eq 1 ]; then
init_iana_prefixes
init_iapd_prefixes
fi
restart_dhcp6s
elif [ $changedEnable -eq 1 ]; then
local ps
ps="Device.DHCPv6.Server.Pool.[Status!Disabled]"
cmclient SETE "$ps" "Disabled"
stop_dhcp6s
fi
;;
Device.DHCPv6.Server.Pool.*.Option.*)
restart_dhcp6s
;;
Device.DHCPv6.Server.Pool.*)
if [ $changedOrder -eq 1 ]; then
help_sort_orders "$obj" "$oldOrder" \
"$newOrder" "$AH_NAME"
fi
if [ $changedEnable -eq 1 -o \
$changedIANAEnable -eq 1 -o \
$changedIANAManualPrefixes -eq 1 -o \
$changedInterface -eq 1 ]; then
[ "$ipv6_enable" = "true" ] && \
align_ianaprefixes "$newEnable" \
"$newIANAEnable" \
"$newIANAManualPrefixes" \
"$newInterface"
fi
if [ $changedEnable -eq 1 -o \
$changedIAPDEnable -eq 1 -o \
$changedIAPDManualPrefixes -eq 1 -o \
$changedInterface -eq 1 ]; then
[ "$ipv6_enable" = "true" ] && \
align_iapdprefixes "$newEnable" \
"$newIAPDEnable" \
"$newIAPDManualPrefixes" \
"$newInterface"
fi
if [ $changedEnable -eq 1 -a \
"$newEnable" = "false" ]; then
cmclient SETE "$obj.Status" Disabled
fi
restart_dhcp6s
;;
esac
}
maybe_add_iana_prefix() {
local pfx="$1" ifobj="" restart=0 auto_add=0 pool="" ianaprefixes="" 
ifobj="${pfx%.IPv6*}"
validate_ianaprefix "$pfx" && auto_add=1
cmclient -v pool GETO \
"DHCPv6.Server.[Enable=true].Pool.*.[Enable=true].[IANAEnable=true].[Interface=$ifobj]"
for pool in $pool; do
cmclient -v ianaprefixes GETV $pool.IANAPrefixes
if help_is_in_list "$ianaprefixes" "$pfx"; then
restart=1
elif [ $auto_add -eq 1 ]; then
ianaprefixes="${ianaprefixes:+$ianaprefixes,}$pfx"
cmclient SET -u "$AH_NAME" "$pool.IANAPrefixes" \
"$ianaprefixes"
restart=1
fi
done
[ $restart -eq 0 ] && return 1 || return 0
}
maybe_add_iapd_prefix() {
local pfx="$1" ifobj="" restart=0 auto_add=0 pool="" iapdprefixes=""
ifobj="${pfx%.IPv6*}"
validate_iapdprefix "$pfx" && auto_add=1
cmclient -v pool GETO \
"DHCPv6.Server.[Enable=true].Pool.*.[Enable=true].[IAPDEnable=true].[Interface=$ifobj]"
for pool in $pool; do
cmclient -v iapdprefixes GETV $pool.IAPDPrefixes
if help_is_in_list "$iapdprefixes" "$pfx"; then
restart=1
elif [ $auto_add -eq 1 ]; then
iapdprefixes="${iapdprefixes:+$iapdprefixes,}$pfx"
cmclient SETE "$pool.IAPDPrefixes" "$iapdprefixes"
restart=1
fi
done
[ $restart -eq 0 ] && return 1 || return 0
}
cmclient -v ipv6_enable GETV "Device.IP.IPv6Enable"
cmclient -v dhcpd_enable GETV "Device.DHCPv6.Server.Enable"
case "$1" in
init)
if [ "$dhcpd_enable" = "true" ]; then
if [ "$ipv6_enable" = "true" ]; then
init_iana_prefixes
init_iapd_prefixes
restart_dhcp6s
else
local ps
ps="Device.DHCPv6.Server.Pool.[Status!Disabled]"
cmclient SETE "$ps" "Disabled"
stop_dhcp6s
fi
fi
exit 0
;;
restart)
restart_dhcp6s
exit 0
;;
ifchange)
local intf
cmclient -v intf GETO \
"Device.DHCPv6.Server.[Enable=true].Pool.*.[Interface=$2]"
if [ ${#intf} -ne 0 ]; then
restart_dhcp6s
fi
exit 0
;;
prefixadd|prefixchange)
local restart=0
maybe_add_iana_prefix "$2" && restart=1
maybe_add_iapd_prefix "$2" && restart=1
[ $restart -eq 1 ] && restart_dhcp6s
exit 0
;;
prefixdel)
local pool
del_obj=$2
restart=0
cmclient -v pool GETO \
"Device.DHCPv6.Server.[Enable=true].Pool.*.[Enable=true].[IANAEnable=true].[IANAPrefixes>$del_obj]"
for pool in $pool; do
ianaprefixes=""
set -f
IFS=","
set -- `cmclient GETV $pool.IANAPrefixes`
unset IFS
set +f
for arg; do
[ "$arg" != "$del_obj" ] && \
ianaprefixes="${ianaprefixes:+$ianaprefixes,}$arg" || \
restart=1
done
cmclient SET -u "$AH_NAME" \
"$pool".IANAPrefixes "$ianaprefixes"
done
cmclient -v pool GETO \
"Device.DHCPv6.Server.Pool.*.[IANAManualPrefixes>$del_obj]"
for pool in $pool; do
ianaprefixes=""
set -f
IFS=","
set -- `cmclient GETV $pool.IANAManualPrefixes`
unset IFS
set +f
for arg; do
[ "$arg" != "$del_obj" ] && \
ianaprefixes="${ianaprefixes:+$ianaprefixes,}$arg" || \
restart=1
done
cmclient SET -u "$AH_NAME" "$pool".IANAManualPrefixes \
"$ianaprefixes"
done
cmclient -v ipv6_pools GETO \
"Device.DHCPv6.Server.[Enable=true].Pool.*.[Enable=true].[IAPDEnable=true].[IAPDPrefixes>$del_obj]"
for pool in $ipv6_pools; do
iapdprefixes=""
cmclient -v cmprefixes GETV $pool.IAPDPrefixes
set -f
IFS=","
set -- $cmprefixes
unset IFS
set +f
for arg; do
[ "$arg" != "$del_obj" ] && \
iapdprefixes="${iapdprefixes:+$iapdprefixes,}$arg" || \
restart=1
done
cmclient SETE "$pool".IAPDPrefixes "$iapdprefixes"
done
cmclient -v ipv6_pools GETO \
"Device.DHCPv6.Server.Pool.*.[IAPDManualPrefixes>$del_obj]"
for pool in $ipv6_pools; do
iapdprefixes=""
cmclient -v cmprefixes GETV $pool.IAPDManualPrefixes
set -f
IFS=","
set -- $cmprefixes
unset IFS
set +f
for arg; do
[ "$arg" != "$del_obj" ] && \
iapdprefixes="${iapdprefixes:+$iapdprefixes,}$arg" || \
restart=1
done
cmclient SETE "$pool".IAPDManualPrefixes "$iapdprefixes"
done
[ $restart -eq 1 ] && restart_dhcp6s
exit 0
;;
clientchange)
create_pool_leases_file $2
;;
esac
case "$op" in
a)
service_add
;;
d)
service_delete
;;
s)
service_config
;;
esac
exit 0
