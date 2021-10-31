#!/bin/sh
AH_NAME="odhcp6c_hook"
. /etc/ah/helper_serialize.sh && help_serialize "$AH_NAME" > /dev/null
. /etc/ah/helper_functions.sh
. /etc/ah/IPv6_helper_functions.sh
deprecate_prefix() {
local deprecate_status tmp_setm valid_lifetime valid_lifetime_sec obj_prefix="$1"
local pref_lifetime pref_lifetime_sec
local curr_time=`date -u +"%s"`
local curr_uptime
IFS=. read curr_uptime _ < /proc/uptime
cmclient -v deprecate_status GETV "$obj_prefix.PrefixStatus"
[ "$deprecate_status" = "Deprecated" ] && continue
cmclient -v valid_lifetime GETV "$obj_prefix.ValidLifetime"
valid_lifetime_sec=$(help_ipv6_lft_to_secs $valid_lifetime $curr_time)
pref_lifetime=$(help_ipv6_now)
pref_lifetime_sec=$(help_ipv6_lft_to_secs $pref_lifetime $curr_time)
[ $valid_lifetime_sec -gt 7200 ] && valid_lifetime="$(help_ipv6_lft_from_secs 7200 $curr_time)"
tmp_setm="${tmp_setm:+$tmp_setm	}$obj_prefix.PreferredLifetime=$pref_lifetime"
tmp_setm="${tmp_setm:+$tmp_setm	}$obj_prefix.ValidLifetime=$valid_lifetime"
tmp_setm="${tmp_setm:+$tmp_setm	}$obj_prefix.X_ADB_Preferred=$((pref_lifetime_sec + curr_uptime))"
tmp_setm="${tmp_setm:+$tmp_setm	}$obj_prefix.X_ADB_Valid=$((valid_lifetime_sec + curr_uptime))"
cmclient SETM "$tmp_setm"
}
set_single_addr_block() {
local setm obj ipintf="$1" single_addr_block="$2" curr_time="$3"
set -f
IFS=","
set -- $single_addr_block
unset IFS
set +f
local addr=${1%%/*} # IPv6Address
local plt=$2	    # PreferredLifetime
local vlt=$3	    # ValidLifetime
cmclient -v obj GETO "$ipintf.IPv6Address.[IPAddress=$addr].[Origin=DHCPv6]"
[ ${#obj} -eq 0 ] && cmclient -v obj ADD "$ipintf.IPv6Address" && obj="$ipintf.IPv6Address.$obj"
setm="${setm:+$setm	}$obj.IPAddress=$addr"
setm="${setm:+$setm	}$obj.Origin=DHCPv6"
setm="${setm:+$setm	}$obj.PreferredLifetime=`help_ipv6_lft_from_secs "$plt" "$curr_time"`"
setm="${setm:+$setm	}$obj.ValidLifetime=`help_ipv6_lft_from_secs "$vlt" "$curr_time"`"
setm="${setm:+$setm	}$obj.Enable=true"
cmclient -v _ SETM "$setm"
}
clean_addr(){
local obj_addr addr ipintf="$1" addr_blocks="$2"
cmclient -v obj_addr GETO "$ipintf.IPv6Address.[Origin=DHCPv6]"
for obj_addr in $obj_addr; do
cmclient -v addr GETV "$obj_addr.IPAddress"
case "$addr_blocks" in
*"$addr"*)
;;
*)
cmclient -v _ DEL "$obj_addr"
;;
esac
done
}
set_single_prefix_block() {
local setm pobj ipintf="$1" synced="$2" local_uptime="$3" single_prefix_block="$4" curr_time="$5"
set -f
IFS=","
set -- $single_prefix_block
unset IFS
set +f
local prefix=$1		# IPv6Prefix (IPv6Address/length)
local plt=$2		# PreferredLifetime
local vlt=$3		# ValidLifetime
cmclient -v pobj GETO "$ipintf.IPv6Prefix.[Enable=true].[Prefix=$prefix].[Origin=Static].[StaticType=PrefixDelegation]"
if [ ${#pobj} -ne 0 ]; then
setm="${setm:+$setm	}$pobj.Origin=Static"
setm="${setm:+$setm	}$pobj.StaticType=PrefixDelegation"
cmclient -v _ DEL $ipintf.IPv6Prefix.[Prefix=$prefix].[Origin=PrefixDelegation]
else
cmclient -v pobj GETO "$ipintf.IPv6Prefix.[Prefix=$prefix].[Origin=PrefixDelegation]"
[ ${#pobj} -eq 0 ] && cmclient -v pobj ADD "$ipintf.IPv6Prefix" && pobj="$ipintf.IPv6Prefix.$pobj"
setm="${setm:+$setm	}$pobj.Origin=PrefixDelegation"
setm="${setm:+$setm	}$pobj.StaticType=Inapplicable"
setm="${setm:+$setm	}$pobj.Enable=true"
fi
setm="${setm:+$setm	}$pobj.Autonomous=true"
setm="${setm:+$setm	}$pobj.OnLink=true"
setm="${setm:+$setm	}$pobj.Status=Enabled"
setm="${setm:+$setm	}$pobj.Prefix=$prefix"
setm="${setm:+$setm	}$pobj.PreferredLifetime=`help_ipv6_lft_from_secs "$plt" "$curr_time"`"
setm="${setm:+$setm	}$pobj.ValidLifetime=`help_ipv6_lft_from_secs "$vlt" "$curr_time"`"
if [ "$synced" -eq 0 ]; then
setm="${setm:+$setm	}$pobj.PrefixStatus=Unknown"
setm="${setm:+$setm	}$pobj.X_ADB_Preferred=$((plt + local_uptime))"
setm="${setm:+$setm	}$pobj.X_ADB_Valid=$((vlt + local_uptime))"
fi
cmclient -v _ SETM "$setm"
}
clean_prefix() {
local obj_prefix obj_prefix_tmp origin prefix="" ipintf="$1" prefix_blocks="$2"
cmclient -v obj_prefix GETO "$ipintf.IPv6Prefix.[Origin=PrefixDelegation]"
cmclient -v obj_prefix_tmp GETO "$ipintf.IPv6Prefix.[Origin=Static].[StaticType=PrefixDelegation]"
obj_prefix="${obj_prefix:+$obj_prefix }""${obj_prefix_tmp}"
for obj_prefix in $obj_prefix; do
cmclient -v prefix GETV "$obj_prefix.Prefix"
[ ${#prefix} -eq 0 ] && continue
case "$prefix_blocks" in
*"$prefix"*)
;;
*)
deprecate_prefix "$obj_prefix"
;;
esac
done
}
update_server() {
local setm clientobj="$1" server_duid="$2" server_addr="$3" name="$4"
[ "$name" != 'serverobj' ] && local serverobj
cmclient -v serverobj GETO "$clientobj.Server.[DUID=$server_duid]"
[ ${#serverobj} -eq 0 ] && cmclient -v serverobj ADD "$clientobj.Server" && serverobj="$clientobj.Server.$serverobj"
setm="${setm:+$setm	}$serverobj.SourceAddress=$server_addr"
setm="${setm:+$setm	}$serverobj.DUID=$server_duid"
setm="${setm:+$setm	}$serverobj.InformationRefreshTime=0001-01-01T00:00:00Z"
cmclient -v _ SETM "$setm"
eval $name='$serverobj'
}
update_routes() {
local root="Device.Routing.Router.1.IPv6Forwarding" ifobj="$1" name="$2" curr_time="$3"
[ "$name" != 'setm' ] && local setm=""
for rt in $DHCP_ROUTES; do
set -f
IFS=','
set -- $rt
local DestIPPrefix="$1"
local NextHop="$2"
local lifetime="$3"
unset IFS
local obj
cmclient -v obj GETO "${root}.*.[Interface=$ifobj].[NextHop=$NextHop].[DestIPPrefix=$DestIPPrefix]"
if [ ${#obj} -eq 0 -a "$lifetime" != "0" ]; then
cmclient -v obj ADDS "${root}"
obj="${root}.${obj}"
elif [ ${#obj} -ne 0 -a "$lifetime" = "0" ]; then
cmclient -v _ DEL "$obj"
continue
fi
setm="${setm:+$setm	}$obj.Interface=$ifobj"
setm="${setm:+$setm	}$obj.Origin=DHCPv6"
setm="${setm:+$setm	}$obj.Enable=true"
setm="${setm:+$setm	}$obj.DestIPPrefix=$DestIPPrefix"
setm="${setm:+$setm	}$obj.ExpirationTime=`help_ipv6_lft_from_secs "$lifetime" "$curr_time"`"
setm="${setm:+$setm	}$obj.NextHop=$NextHop"
done
eval $name='$setm'
}
update_onlink_prefixes() {
local root="Device.Routing.Router.1.IPv6Forwarding" ifobj="$1" name="$2" curr_time="$3"
[ "$name" != 'setm' ] && local setm=""
for pfx in $RT_PREFIXES; do
set -f
IFS=','
set -- $pfx
local DestIPPrefix="$1"
local lifetime="$2"
unset IFS
local obj
cmclient -v obj GETO "${root}.*.[Interface=$ifobj].[DestIPPrefix=$DestIPPrefix].[NextHop=""]"
if [ ${#obj} -eq 0 -a "$lifetime" != "0" ]; then
cmclient -v obj ADDS "${root}"
obj="${root}.${obj}"
elif [ ${#obj} -ne 0 -a "$lifetime" = "0" ]; then
cmclient -v _ DEL "$obj"
continue
fi
setm="${setm:+$setm	}$obj.Interface=$ifobj"
setm="${setm:+$setm	}$obj.Origin=DHCPv6"
setm="${setm:+$setm	}$obj.Enable=true"
setm="${setm:+$setm	}$obj.DestIPPrefix=$DestIPPrefix"
setm="${setm:+$setm	}$obj.ExpirationTime=`help_ipv6_lft_from_secs "$lifetime" "$curr_time"`"
done
eval $name='$setm'
}
opt_referenced_by_server() {
local option tag="$1" clientobj="$2"
cmclient -v option GETO "Device.DHCPv6.Server.[Enable=true].Pool.[Enable=true].*.Option.[Enable=true].[Tag=$tag].[PassthroughClient=$clientobj]"
[ ${#option} -ne 0 ] && return 0 || return 1
}
restart_dhcpv6_server() {
/etc/ah/DHCPv6Server.sh restart
}
restart_radvd() {
cmclient SET Device.RouterAdvertisement.[Enable=true].Enable true
}
update_options() {
local kick_dhcp_server= kick_radvd= tag setm obj ipintf="$1" clientobj="$2" serverobj="$3" curr_time="$4"
cmclient -v _ DEL "$clientobj.ReceivedOption.[Server=$serverobj]"
cmclient -v _ DEL "Device.DNS.**.[Type=DHCPv6].[Interface=$ipintf]"
for tag in $OPTION_CODES; do
setm=""
cmclient -v obj ADD "$clientobj.ReceivedOption"
obj="$clientobj.ReceivedOption.$obj"
eval local opt=\${OPTION_${tag}%% *}
eval OPTION_${tag}=\${OPTION_${tag}#* }
setm="${setm:+$setm	}$obj.Tag=$tag"
setm="${setm:+$setm	}$obj.Value=$opt"
setm="${setm:+$setm	}$obj.Server=$serverobj"
if opt_referenced_by_server "$tag" "$clientobj"; then
kick_dhcp_server="yep"
fi
case "$tag" in
23)
for dns in $RDNSS; do
cmclient -v obj GETO "Device.DNS.Client.Server.[DNSServer=$dns].[Type=DHCPv6]"
[ ${#obj} -eq 0 ] && cmclient -v obj ADDS "Device.DNS.Client.Server" && obj="Device.DNS.Client.Server.$obj"
setm="${setm:+$setm	}$obj.DNSServer=$dns"
setm="${setm:+$setm	}$obj.Interface=$ipintf"
setm="${setm:+$setm	}$obj.Type=DHCPv6"
setm="${setm:+$setm	}$obj.Enable=true"
case "$dns" in
*:*)	setm="${setm:+$setm	}$obj.X_ADB_PrioBase=0" ;;
*)	setm="${setm:+$setm	}$obj.X_ADB_PrioBase=1" ;;
esac
cmclient -v obj GETO "Device.DNS.Relay.Forwarding.[DNSServer=$dns].[Type=DHCPv6]"
[ ${#obj} -eq 0 ] && cmclient -v obj ADDS "Device.DNS.Relay.Forwarding" && obj="Device.DNS.Relay.Forwarding.$obj"
setm="${setm:+$setm	}$obj.DNSServer=$dns"
setm="${setm:+$setm	}$obj.Interface=$ipintf"
setm="${setm:+$setm	}$obj.Type=DHCPv6"
setm="${setm:+$setm	}$obj.Enable=true"
case "$dns" in
*:*)	setm="${setm:+$setm	}$obj.X_ADB_PrioBase=0" ;;
*)	setm="${setm:+$setm	}$obj.X_ADB_PrioBase=1" ;;
esac
done
kick_radvd=1
;;
24)
kick_radvd=1
;;
242)
update_routes "$ipintf" "setm" "$curr_time"
;;
243)
update_onlink_prefixes "$ipintf" "setm" "$curr_time"
;;
esac
cmclient -v _ SETM "$setm"
done
[ -n "$kick_dhcp_server" ] && restart_dhcpv6_server
[ -n "$kick_radvd" ] && restart_radvd
}
add() {
local obj=`help_obj_from_ifname_get "$IFACE"`
[ ${#obj} -eq 0 ] && return
local ipintf=`ip_interface_get "$obj"`
[ ${#ipintf} -eq 0 ] && return
local clientobj uptime curr_time synced correct_prefixes serverobj prefix= postfix
cmclient -v clientobj GETO "Device.DHCPv6.Client.[Interface=$ipintf]"
IFS=. read uptime _ < /proc/uptime
unset IFS
help_serialize IPv6Synchronize >/dev/null
cmclient -v synced GETV Device.Time.Status
[ "$synced" = "Synchronized" ] && synced=1 || synced=0
curr_time=`date -u +"%s"`
clean_addr "$ipintf" "$ADDRESSES"
for single_addr_block in $ADDRESSES; do
set_single_addr_block "$ipintf" "$single_addr_block" "$curr_time"
done
for single_prefix_block in $PREFIXES; do
prefix=${single_prefix_block%%,*}
postfix=${single_prefix_block#*,}
correct_prefixes="${correct_prefixes:+$correct_prefixes }$(prefix_from_addr_len "${prefix%%/*}" "${prefix##*/}"),$postfix"
done
clean_prefix "$ipintf" "$correct_prefixes"
for single_prefix_block in $correct_prefixes; do
set_single_prefix_block "$ipintf" "$synced" "$uptime" "$single_prefix_block" "$curr_time"
done
update_server "$clientobj" "$SERVERID" "$SERVER" "serverobj"
update_options "$ipintf" "$clientobj" "$serverobj" "$curr_time"
case "$EVENT_TYPE" in
bound|rebound) help_ipv6_forwarding_static_refresh "$ipintf" ;;
esac
cmclient SAVE
}
disable() {
local obj=`help_obj_from_ifname_get "$IFACE"`
[ ${#obj} -eq 0 ] && return
local ipintf=`ip_interface_get "$obj"`
[ ${#ipintf} -eq 0 ] && return
cmclient -v _ SET "$ipintf.IPv6Prefix.[Origin=PrefixDelegation].Status" "Disabled"
cmclient -v _ SET "$ipintf.IPv6Address.[Origin=DHCPv6].Status" "Disabled"
}
remove() {
local obj=`help_obj_from_ifname_get "$IFACE"`
[ ${#obj} -eq 0 ] && return
local ipintf=`ip_interface_get "$obj"`
[ ${#ipintf} -eq 0 ] && return
cmclient -v _ -u dhcp_release DEL "$ipintf.IPv6Prefix.[Origin=PrefixDelegation]"
cmclient -v _ SET "$ipintf.IPv6Prefix.[Origin=Static].[StaticType=PrefixDelegation].Status" "Disabled"
cmclient -v _ DEL "$ipintf.IPv6Address.[Origin=DHCPv6]"
cmclient -v _ DEL "Device.Routing.Router.1.IPv6Forwarding.*.[Interface=$ipintf].[Origin=DHCPv6]"
cmclient -v _ DEL "Device.DNS.**.[Type=DHCPv6].[Interface=$ipintf]"
cmclient SAVE
}
remove_addresses() {
local obj=`help_obj_from_ifname_get "$IFACE"`
[ ${#obj} -eq 0 ] && return 0
local ipintf=`ip_interface_get "$obj"`
[ ${#ipintf} -eq 0 ] && return 0
cmclient -v _ DEL "$ipintf.IPv6Address.[Origin=DHCPv6]"
cmclient SAVE
}
update_information() {
local obj=`help_obj_from_ifname_get "$IFACE"`
[ ${#obj} -eq 0 ] && return
local ipintf=`ip_interface_get "$obj"`
[ ${#ipintf} -eq 0 ] && return
local clientobj serverobj curr_time
cmclient -v clientobj GETO "Device.DHCPv6.Client.[Interface=$ipintf]"
update_server "$clientobj" "$SERVERID" "$SERVER" "serverobj"
curr_time=`date -u +"%s"`
update_options "$ipintf" "$clientobj" "$serverobj" "$curr_time"
}
fill_in_duid() {
[ ${#IFACE} -ne 0 ] || return 1
[ ${#CLIENTID} -ne 0 ] || return 1
local obj=`help_obj_from_ifname_get "$IFACE"`
[ ${#obj} -ne 0 ] || return 1
local ifobj=`ip_interface_get "$obj"`
[ ${#ifobj} -ne 0 ] || return 1
local clientobj
cmclient -v clientobj GETO "Device.DHCPv6.Client.[Interface=${ifobj}]"
[ ${#clientobj} -ne 0 ] || return 1
local lock_name="DHCPv6Client.${clientobj#Device.DHCPv6.Client.}"
cmclient -v _ -u "$lock_name" SET "${clientobj}.DUID" "$CLIENTID"
}
case "$EVENT_TYPE" in
started)
fill_in_duid
;;
updated|bound|rebound)
add
;;
unbound)
disable
remove
;;
declined)
remove_addresses
;;
informed)
update_information
;;
stopped)
disable
;;
esac
exit 0
