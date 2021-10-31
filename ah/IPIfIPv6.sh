#!/bin/sh
AH_NAME="IPIfIPv6"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "boot" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/IPv6_helper_firewall.sh
create_slot_child_prefix() {
[ $2 -ge $4 ] && return 1
local parent_length=$2
local child_length=$4
local parent_addr=$(ipv6_hex_to_bin "$(help_ipv6_expand $1)")
local child_addr=$(ipv6_hex_to_bin "$(help_ipv6_expand $3)")
local result="`expr substr $parent_addr 1 $parent_length`""`expr substr $child_addr $(($parent_length+1)) $(($child_length-$parent_length))`"
local index=$((128-$child_length))
while [ $index -gt 0 ]
do
result="$result"0
index=$(($index-1))
done
echo "$(ipv6_short_format $(help_split_chars_with_sep 4 : $(ipv6_bin_to_hex $result 128)))/$child_length"
}
update_ACL_rules() {
local _ACLState="" _bridge=""
cmclient -v _ACLState GETV Device.UserInterface.X_ADB_LocalAccess.X_ADB_AccessControlEnable
if [ "$_ACLState" = "true" ]; then
cmclient -v _bridge GETO Device.Bridging.Bridge.*.Port.*.[ManagementPort=true].[Name="$2"]
[ -n "$_bridge" ] && help_ip6tables -$1 GUILocalIn -i $2 -d $3 -j GUILocalIn_
fi
}
reload_user_interface_local_remote_access() {
local ipv6_interface=$1 ipv6_interface_upstream="" gui_local_access="" gui_remote_access="" httpd_bound_interfaces=""
cmclient -v gui_local_access GETV "Device.UserInterface.X_ADB_LocalAccess.Enable"
cmclient -v gui_remote_access GETV "Device.UserInterface.RemoteAccess.Enable"
cmclient -v ipv6_interface_upstream GETV "$ipv6_interface.X_ADB_Upstream"
if [ "$gui_local_access" = "true" ]; then
cmclient -v httpd_bound_interfaces GETV Device.UserInterface.X_ADB_LocalAccess.Interface
if [ ${#httpd_bound_interfaces} -gt 0 ]; then
if help_is_in_list "$httpd_bound_interfaces" "$ipv6_interface"; then
cmclient SET Device.UserInterface.X_ADB_LocalAccess.Reset true
fi
else
if [ "$ipv6_interface_upstream" = "false" ]; then
cmclient SET Device.UserInterface.X_ADB_LocalAccess.Reset true
fi
fi
fi
if [ "$gui_remote_access" = "true" ]; then
cmclient -v httpd_bound_interfaces GETV Device.UserInterface.RemoteAccess.X_ADB_Interface
if [ ${#httpd_bound_interfaces} -gt 0 ]; then
if help_is_in_list "$httpd_bound_interfaces" "$ipv6_interface"; then
cmclient SET Device.UserInterface.RemoteAccess.X_ADB_Reset true
fi
else
if [ "$ipv6_interface_upstream" = "true" ]; then
cmclient SET Device.UserInterface.RemoteAccess.X_ADB_Reset true
fi
fi
fi
}
service_get_ipv6_lifetime () {
local new_lt=$1 curr_sec=$2 result="0"
if islifetimedefined "$new_lt" ; then
if islifetimeinfinity "$new_lt" ; then
result="forever"
elif [ -n  "$new_lt" ] ; then
result=`help_ipv6_lft_to_secs "$new_lt" "$curr_sec"`
[ $result -lt 0 ] && result="0"
fi
fi
echo "$result"
}
service_reconf_ipv6_address () {
local to_delete="$1" ipv6address_status="$oldStatus"
local lifetime_status new_addr_status ipv6_addr_cmd
local old_valid=0 new_valid=0
if [ "$user" != "eh_ipv6" ]; then
local ip_enable ipif_enable ipif_status ip_ifname lowlayer_path
local ipifipv6_enable ipv6_command
local ipv6prefix_enable ipv6_prefixvalue ipv6_prefixlen staticType prefixStatus
cmclient -v ip_enable GETV "Device.IP.IPv6Enable"
cmclient -v ipif_enable  GETV "$ip_interface.Enable"
cmclient -v ipifipv6_enable  GETV "$ip_interface.IPv6Enable"
cmclient -v ipif_status GETV "$ip_interface.Status"
cmclient -v lowlayer_path GETV "$ip_interface.LowerLayers"
help_lowlayer_ifname_get ip_ifname "$lowlayer_path"
if [ "$newOrigin" = "DHCPv6" -a -z "$newPrefix" ]; then
ipv6prefix_enable="true"
else
cmclient -v staticType GETV "$newPrefix.StaticType"
if [ "$staticType" = "Child" ]; then
cmclient -v prefixStatus GETV "$newPrefix.Status"
[ "$prefixStatus" = "Enabled" ] && ipv6prefix_enable="true" || ipv6prefix_enable="false"
else
cmclient -v ipv6prefix_enable GETV "$newPrefix.Enable"
fi
fi
if [ "$ip_enable" = "true" -a "$ipif_enable" = "true" -a "$ipifipv6_enable" = "true" -a "$ipv6prefix_enable" = "true" ]	\
&& [ -z "$to_delete" -a "$ipif_status" = "Up" -a "$newEnable" = "true" ]; then
ipv6_addr_cmd="add"
ipv6address_status="Enabled"
else
ipv6_addr_cmd="del"
ipv6address_status="Disabled"
cmclient -v prefix_origin GETV "$newPrefix.Origin"
fi
if [ "$ipv6_addr_cmd" != "del" -o "$user" = "dhcp_release" -o "$newOrigin" != "AutoConfigured" -o "$prefix_origin" = "RouterAdvertisement" ]; then
[ -n "$newPrefix" ] && cmclient -v ipv6_prefixvalue GETV "$newPrefix.Prefix"
[ "$ipv6_addr_cmd" = "add" -a "$changedIPAddress" -eq 0 -a "$changedPrefix" -eq 0 ] && ipv6_addr_cmd="change"
if [ -n "$ipv6_prefixvalue" ]; then
ipv6_prefixlen=${ipv6_prefixvalue##*/}
else
: ${ipv6_prefixlen:=64}
fi
[ -n "$newIPAddress" ] && \
ipv6_command="ip -6 addr $ipv6_addr_cmd $newIPAddress/$ipv6_prefixlen dev $ip_ifname"
if [ "$ipv6_addr_cmd" = "add" ]; then
if [ -n "$oldIPAddress" ]; then
echo "### $AH_NAME: Executing <ip -6 addr del $oldIPAddress/$ipv6_prefixlen dev $ip_ifname> ###" > /dev/console
ip -6 addr del $oldIPAddress/$ipv6_prefixlen dev $ip_ifname
update_ACL_rules D $ip_ifname $oldIPAddress
fi
fi
if [ -n "$ipv6_command" ]; then
if [ "$ipv6_addr_cmd" = "add" -o "$ipv6_addr_cmd" = "change" ]; then
lifetime_status=`get_status_from_lifetime "$newPreferredLifetime" "$newValidLifetime" ""`
case "$lifetime_status" in
Invalid)
ipv6_command=''
;;
*)
local curr_sec ipv6validlifetime ipv6preflifetime
curr_sec=`date -u +"%s"`
ipv6preflifetime=`service_get_ipv6_lifetime $newPreferredLifetime $curr_sec`
ipv6validlifetime=`service_get_ipv6_lifetime $newValidLifetime $curr_sec`
ipv6_command="$ipv6_command preferred_lft $ipv6preflifetime valid_lft $ipv6validlifetime"
;;
esac
if [ -n "$ipv6_command" ]; then
echo "### $AH_NAME: Executing <$ipv6_command> ###" > /dev/console
$ipv6_command
[ "$ipv6_addr_cmd" = "add" ] && \
update_ACL_rules A $ip_ifname $newIPAddress
fi
else
echo "### $AH_NAME: Executing <$ipv6_command> ###" > /dev/console
$ipv6_command
[ "$ipv6_addr_cmd" = "del" ] && update_ACL_rules D $ip_ifname $newIPAddress
lifetime_status="Inaccessible"
fi
fi
fi
fi
if [ "$changedIPAddress" -eq 1 -a "$setIPAddressStatus" -eq 0 ] || [ "$ipv6_addr_cmd" = "del" ] ; then
new_addr_status="Invalid"
elif [ -n "$lifetime_status" -a "$lifetime_status" != "Preferred" ]; then
new_addr_status=$lifetime_status
else
new_addr_status=$newIPAddressStatus
fi
[ -n "$new_addr_status" ] && cmclient SETE "$obj.IPAddressStatus" "$new_addr_status"
[ "$oldIPAddressStatus" = "Preferred" -a "$oldStatus" = "Enabled" ] && old_valid=1
[ "$new_addr_status" = "Preferred" -a "$ipv6address_status" = "Enabled" ] && new_valid=1
if [ $new_valid -ne $old_valid ]; then
cmclient -u "IPIfIPv6$obj" SET "$obj.Status $ipv6address_status" > /dev/null
/etc/ah/TR069.sh IP_IF_CHANGED "$ip_interface"
/etc/ah/DHCPv6Server.sh ifchange "$ip_interface"
elif [ "$ipv6address_status" != "$oldStatus" ]; then
cmclient SETE "$obj.Status $ipv6address_status"
fi
reload_user_interface_local_remote_access $ip_interface
}
service_reconf_ipv6_prefix () {
for ipv6_obj in `cmclient GETO "$ip_interface.IPv6Address.[Prefix=$obj].[Enable=true]"`
do
cmclient SET "$ipv6_obj.Enable" "true"
done
if [ "$newStaticType" = "Child" ]; then
if [ "$newEnable" = "false" -a "$oldEnable" = "true" ]; then
local setm
setm="${setm:+$setm	}$obj.Status=Disabled"
setm="${setm:+$setm	}$obj.Prefix=	"
cmclient -u "${AH_NAME}${obj}" SETM "$setm" > /dev/null
fi
else
local status_="Disabled"
[ "$newEnable" = "true" ] && status_="Enabled"
cmclient SETE "$obj.Status" "$status_"
fi
}
service_reconf_ipv6_static_pd () {
local setm
if [ "$newEnable" = "true" ]; then
for ipv6_obj in `cmclient GETO "Device.IP.Interface.[X_ADB_Upstream=false].IPv6Prefix.[ParentPrefix=$obj].[Enable=true]"`
do
if [ "$newStatus" = "Enabled" ]; then
local child_bit="`cmclient GETV $ipv6_obj.ChildPrefixBits`"
[ -z "$child_bit" ] && continue
local child_prefix=$(create_slot_child_prefix "${newPrefix%%/*}" "${newPrefix##*/}" "${child_bit%%/*}" "${child_bit##*/}")
[ -z "$child_prefix" ] && continue
setm="${setm:+$setm	}$ipv6_obj.Status=Enabled"
setm="${setm:+$setm	}$ipv6_obj.Prefix=$child_prefix"
setm="${setm:+$setm	}$ipv6_obj.PreferredLifetime=$newPreferredLifetime"
setm="${setm:+$setm	}$ipv6_obj.ValidLifetime=$newValidLifetime"
setm="${setm:+$setm	}$ipv6_obj.X_ADB_Valid=$newX_ADB_Valid"
setm="${setm:+$setm	}$ipv6_obj.X_ADB_Preferred=$newX_ADB_Preferred"
else
setm="${setm:+$setm	}$ipv6_obj.Status=Disabled"
setm="${setm:+$setm	}$ipv6_obj.Prefix="
fi
done
else
for ipv6_obj in `cmclient GETO "Device.IP.Interface.[X_ADB_Upstream=false].IPv6Prefix.[ParentPrefix=$obj].[Enable=true]"`
do
setm="${setm:+$setm	}$ipv6_obj.Status=Disabled"
setm="${setm:+$setm	}$ipv6_obj.Prefix="
done
fi
[ -n "$setm" ] && cmclient -u "${AH_NAME}${obj}" SETM "$setm" >/dev/null
}
service_delete_ipv6 () {
local ip_interface="${obj%.IPv6*}"
local pending
local singleobj
case "$obj" in
*"IPv6Prefix"*)
for ipv6_addr in `cmclient GETO "$ip_interface.IPv6Address.[Prefix=$obj]"`
do
cmclient -u "$user" DEL "$ipv6_addr" > /dev/null
done
cmclient DEL Device.RouterAdvertisement.InterfaceSetting.[Interface=${ip_interface}].Option.[Tag=24].[Value=${obj}.Prefix]
cmclient -u "$user" DEL "Device.IP.Interface.[X_ADB_Upstream=false].IPv6Prefix.[ParentPrefix=$obj]" > /dev/null
radvd_need_reconf "$obj" "$ip_interface" "$newOrigin" "$newStaticType" "DEL"
/etc/ah/DHCPv6Server.sh prefixdel "$obj"
if [ "$newOrigin" = "Static" ]; then
cmclient DEL "Device.X_ADB_Time.Event.*.[Alias=$obj]"
cmclient -v lowlayer_path GETV "$ip_interface.LowerLayers"
help_lowlayer_ifname_get ip_ifname "$lowlayer_path"
if [ -n "$ip_ifname" ] && [ -n "$newPrefix" ]; then
ip -6 route del $newPrefix dev $ip_ifname
fi
fi
;;
*"IPv6Address"*)
service_reconf_ipv6_address "true"
;;
esac
}
update_child_prefixes () {
local setm child_global_address ds_ifaces_obj additional_bits=0 downstream_amount=0
cmclient -v ds_ifaces_obj GETO "Device.IP.Interface.[X_ADB_Upstream=false]"
local addr=${newPrefix%%/*} # IPv6Address
local length=${newPrefix##*/} # length
local route_info_option_for_ra
local ra_interface_setting
local curr_sec=`date -u +"%s"` ipv6validlifetime=-1
ipv6validlifetime=`service_get_ipv6_lifetime $newValidLifetime $curr_sec`
for iface_index in $ds_ifaces_obj; do
iface_index=${iface_index##*.}
downstream_amount=$(($downstream_amount+1))
[ $additional_bits -lt $iface_index ] && additional_bits=$iface_index
done
if [ $downstream_amount -eq 0 ]; then
return 1
elif [ $downstream_amount -eq 1 ]; then
additional_bits=0
elif [ $downstream_amount -gt 1 -a -n "$length" -a $length -ge 64 ]; then
additional_bits=0
set -- $ds_ifaces_obj
ds_ifaces_obj="$1"
else
additional_bits=$(ipv6_hex_to_bin $additional_bits ${#additional_bits})
additional_bits=${#additional_bits}
fi
for lanintf in $ds_ifaces_obj; do
local child_prefix=""
if [ -n "$addr" -a -n "$length" ]; then
child_prefix=$(help_create_child_prefix "$addr" "$length" "${lanintf##*.}" "$additional_bits")
fi
[ -z "$child_prefix" ] && continue
[ ${child_prefix##*/} -gt 64 ] && continue
if [ ${child_prefix##*/} -lt 64 ]; then
child_prefix="${child_prefix%%/*}/64"
fi
local child_obj=`cmclient GETO "$lanintf.IPv6Prefix.[ParentPrefix=$obj]"`
[ -z "$child_obj" ] && local child_obj="$lanintf.IPv6Prefix.`cmclient ADD "$lanintf".IPv6Prefix`" && cmclient SETS "$child_obj" 0 >/dev/null
setm="${setm:+$setm	}$child_obj.Prefix=$child_prefix"
setm="${setm:+$setm	}$child_obj.Origin=Child"
setm="${setm:+$setm	}$child_obj.StaticType=Inapplicable"
setm="${setm:+$setm	}$child_obj.OnLink=$newOnLink"
setm="${setm:+$setm	}$child_obj.Autonomous=$newAutonomous"
setm="${setm:+$setm	}$child_obj.ParentPrefix=$obj"
setm="${setm:+$setm	}$child_obj.PreferredLifetime=$newPreferredLifetime"
setm="${setm:+$setm	}$child_obj.ValidLifetime=$newValidLifetime"
setm="${setm:+$setm	}$child_obj.Enable=$newEnable"
setm="${setm:+$setm	}$child_obj.Status=$newStatus"
setm="${setm:+$setm	}$child_obj.PrefixStatus=$newPrefixStatus"
setm="${setm:+$setm	}$child_obj.X_ADB_Preferred=${newX_ADB_Preferred:-0}"
setm="${setm:+$setm	}$child_obj.X_ADB_Valid=${newX_ADB_Valid:-0}"
local addr_obj=`cmclient GETO "$lanintf.IPv6Address.[Prefix=$child_obj]"`
[ -z "$addr_obj" ] && local addr_obj="$lanintf.IPv6Address.`cmclient ADD "$lanintf".IPv6Address`" && cmclient SETS "$addr_obj" 0 >/dev/null
help_lowest_ifname_get ifName $lanintf
child_global_address="${child_prefix%%/*}$(ipv6_from_mac_to_id $ifName)"
child_global_address=`ipv6_short_format $child_global_address`
setm="${setm:+$setm	}$addr_obj.IPAddress=$child_global_address"
setm="${setm:+$setm	}$addr_obj.Origin=AutoConfigured"
setm="${setm:+$setm	}$addr_obj.Prefix=$child_obj"
setm="${setm:+$setm	}$addr_obj.PreferredLifetime=$newPreferredLifetime"
setm="${setm:+$setm	}$addr_obj.ValidLifetime=$newValidLifetime"
setm="${setm:+$setm	}$addr_obj.Enable=true"
setm="${setm:+$setm	}$addr_obj.IPAddressStatus=$newPrefixStatus"
cmclient -v ra_interface_setting GETO Device.RouterAdvertisement.InterfaceSetting.[Interface=$lanintf]
cmclient -v route_info_option_for_ra GETO $ra_interface_setting.Option.[Tag=24].[Value=$newPrefix]
if [ ${#route_info_option_for_ra} -eq 0 ]; then
route_info_option_for_ra="$ra_interface_setting.Option.`cmclient ADDS "$ra_interface_setting".Option.`"
cmclient SETE $route_info_option_for_ra.Tag 24
cmclient SETE $route_info_option_for_ra.X_ADB_Type String
cmclient SETE $route_info_option_for_ra.Value $newPrefix
fi
cmclient SETE $route_info_option_for_ra.X_ADB_OptionLifetime $ipv6validlifetime
done
[ -n "$setm" ] && cmclient -u "${AH_NAME}${obj}" SETM "$setm" >/dev/null
}
ipv6_antispoof() {
local ifname
help_lowlayer_ifname_get ifname "$1"
if [ "$newEnable" = "true" -a -n "$newPrefix" ]; then
help_ip6tables commit
help_ip6tables -D Basic -j Basic_$ifname
help_ip6tables commit noerr
help_ip6tables -N Basic_$ifname
help_ip6tables -I Basic -j Basic_$ifname
help_ip6tables -A Basic_$ifname -o $ifname ! -s $newPrefix -j DROP
help_ip6tables -A Basic_$ifname -i $ifname -s $newPrefix -j DROP
else
help_ip6tables -F Basic_$ifname
help_ip6tables -D Basic -j Basic_$ifname
help_ip6tables -X Basic_$ifname
fi
}
ipv6_prefix_timer_config() {
local action="$1" value="$2" deadline="$3" path="$obj.PrefixStatus"
case "$action" in
ADD)
local list item
cmclient -v list GETO "Device.X_ADB_Time.Event.[Alias=$obj].Action.[Value=${value}]"
if [ ${#list} -gt 0 ]; then
for item in $list; do
cmclient SET "${item%.Action*}.DeadLine" "${deadline}"
done
else
help_ipv6_action_timer "${action}" "${path}" "${deadline}" "${value}"
fi
;;
DEL)
help_ipv6_action_timer "${action}" "${path}" "" "${value}"
;;
esac
}
ipv6_prefix_lifetime_reconf() {
local time="$1" timer="$2" status_next="$3" status_set="$4"
[ "$time" = "$INFINITE" ] && return 1
if [ "${status_next}" = "Invalid" ]; then
ipv6_prefix_timer_config "DEL" "Deprecated"
ipv6_prefix_timer_config "DEL" "Invalid"
else
if [ ${timer} -gt 0 ]; then
ipv6_prefix_timer_config "ADD" "${status_set}" "${timer}"
else
ipv6_prefix_timer_config "DEL" "${status_set}"
fi
fi
return 0
}
service_reconf_ipv6_prefix_status() {
local next="$1" timer_preferred timer_valid timer_list
local curr_sec=`date -u +"%s"`
[ "$newValidLifetime" != "$INFINITE" ] && timer_valid="$(help_ipv6_lft_to_secs $newValidLifetime $curr_sec)"
[ "$newPreferredLifetime" != "$INFINITE" ] && timer_preferred="$(help_ipv6_lft_to_secs $newPreferredLifetime $curr_sec)"
if [ "$changedPreferredLifetime" = "1" ]; then
if [ "$oldPreferredLifetime" = "$INFINITE" ]; then
[ "$newPreferredLifetime" != "$INFINITE" -a ${timer_preferred} -gt 0 ] && \
ipv6_prefix_timer_config "ADD" "Deprecated" "${timer_preferred}"
else
if ipv6_prefix_lifetime_reconf "$newPreferredLifetime" "${timer_preferred}" "$next" "Deprecated"; then
[ "$next" = "Preferred" -a ${timer_valid} -gt 0 ] && \
ipv6_prefix_timer_config "ADD" "Invalid" "${timer_valid}"
else
ipv6_prefix_timer_config "DEL" "Deprecated"
fi
fi
fi
if [ "$changedValidLifetime" = "1" ]; then
if [ "$next" = "Preferred" -a "$newPreferredLifetime" != "$INFINITE" ]; then
local ntp
cmclient -v ntp GETV Device.Time.Status
[ "${ntp}" = "Synchronized" -a ${timer_preferred} -gt 0 ] && \
ipv6_prefix_timer_config "ADD" "Deprecated" "${timer_preferred}"
fi
if [ "$oldValidLifetime" = "$INFINITE" -a "$newValidLifetime" != "$INFINITE" -a ${timer_valid} -gt 0 ]; then
ipv6_prefix_timer_config "ADD" "Invalid" "${timer_valid}"
elif ! ipv6_prefix_lifetime_reconf "$newValidLifetime" "${timer_valid}" "$next" "Invalid"; then
ipv6_prefix_timer_config "DEL" "Invalid"
fi
fi
}
service_config() {
ip_interface="${obj%.IPv6*}"
case "$obj" in
*"IPv6Prefix"*)
if [ "$user" = "CWMP" ] && [ "$newOrigin" != "Static" ]; then
if help_is_changed Prefix OnLink ChildPrefixBits Autonomous PreferredLifetime ValidLifetime; then
exit 8
fi
fi
local ntp
cmclient -v ntp GETV Device.Time.Status
if [ "$ntp" = "Disabled" -o "$ntp" = "Unsynchronized" ]; then
if [ "$newPreferredLifetime" = "$INFINITE" ] && [ "$newValidLifetime" = "$INFINITE" ]; then
nextPrefixStatus="Preferred"
else
nextPrefixStatus="Unknown"
fi
else
nextPrefixStatus=`get_status_from_lifetime $newPreferredLifetime $newValidLifetime ""`
service_reconf_ipv6_prefix_status "$nextPrefixStatus"
fi
local update_dhcpv6d="no"
if [ $setPrefix -eq 1 -o $changedPreferredLifetime -eq 1 -o $changedValidLifetime -eq 1 ] && [ "$newOrigin" = "PrefixDelegation" -a "$user" != "eh_ipv6" ]; then
[ $changedPrefix -eq 1 ] && ipv6_antispoof "$ip_interface"
update_child_prefixes
fi
if [ "$changedEnable" = "1" -o "$setStatus" = "1" ] && [ "$newStaticType" = "PrefixDelegation" -a "$user" != "eh_ipv6" ]; then
service_reconf_ipv6_static_pd
fi
if [ "$changedEnable" = "1" -o "$newEnable" = "true" ] && [ "$setPrefixStatus" = "0" -a "$user" != "eh_ipv6" -a \
"$newOrigin" != "PrefixDelegation" -a "$newStaticType" != "PrefixDelegation" ]; then
update_dhcpv6d="yes"
service_reconf_ipv6_prefix
fi
if [ "$changedEnable" = "1" -o "$changedPrefixStatus" = 1 -o "$newPrefixStatus" != "$nextPrefixStatus" ] || \
[ "$changedOnLink" = "1" -o "$changedAutonomous" = "1" -o "$changedPreferredLifetime" = "1" -o "$changedValidLifetime" = "1" ]; then
[ "$changedPrefixStatus" = "0" ] && cmclient SETE "$obj.PrefixStatus $nextPrefixStatus"
case "$newOrigin" in
"Static"|"Child"|"AutoConfigured")
if [ "$newOrigin" = "Static" ]; then
cmclient -v lowlayer_path GETV "$ip_interface.LowerLayers"
help_lowlayer_ifname_get ip_ifname "$lowlayer_path"
[ ${#oldPrefix} -gt 0 ] && ip -6 route del "$oldPrefix" dev "$ip_ifname"
[ ${#newPrefix} -gt 0 ] && ip -6 route add "$newPrefix" dev "$ip_ifname"
fi
radvd_need_reconf "$obj" "$ip_interface" "$newOrigin" "$newStaticType" "ADD"
update_dhcpv6d="yes"
;;
esac
fi
if [ "$update_dhcpv6d" = "yes" ]; then
/etc/ah/DHCPv6Server.sh prefixchange "$obj"
fi
;;
*"IPv6Address"*)
if [ "$user" = "CWMP" ] && [ "$newOrigin" != "Static" ]; then
if [ "$changedIPAddress" = "1" ] || [ "$changedPrefix" = "1" ] || [ "$changedPreferredLifetime" = "1" ] || [ "$changedValidLifetime" = "1" ] || [ "$changedAnycast" = "1" ]; then
exit 8
fi
fi
if [ "$changedIPAddress" = "1" -a -n "${newIPAddress}" -a "$user" != "eh_ipv6" ]; then
newIPAddress=`ipv6_short_format $newIPAddress`
cmclient SETE "$obj.IPAddress" "$newIPAddress"
fi
if [ "$changedEnable" = "1" -o "$newEnable" = "true" -o "$changedIPAddressStatus" = "true" ]; then
[ "$newStatus" = "Error" ] || service_reconf_ipv6_address
fi
;;
esac
}
case "$op" in
s)
service_config
;;
d)
service_delete_ipv6
;;
esac
exit 0
