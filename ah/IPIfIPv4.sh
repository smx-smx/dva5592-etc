#!/bin/sh
AH_NAME="IPIfIPv4"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "boot" ] && exit 0
[ "$user" = "skip" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_ipcalc.sh
if [ -x /etc/ah/helper_loopback.sh ]; then
. /etc/ah/helper_loopback.sh
fi
service_get() {
local ip_obj="$1" ip_arg="$2"
case "$ip_arg" in
"X_ADB_UpTime" )
cmclient -v ip_enable GETV "$ip_obj.Enable"
if [ "$ip_enable" = "true" ]; then
IFS=. read t2 _ < /proc/uptime
cmclient -v t1 GETV "$ip_obj.X_ADB_StartTime"
if [ "$t1" != "0" ] && [ "$t1" != "" ]; then
echo $(($t2-$t1))
else
echo "0"
fi
else
echo "0"
fi
;;
*)
echo ""
;;
esac
}
check_and_disable_dhcps() {
local IPObject=$1 dhcp_pool=$2 ip_bridge_net dhcp_net disable_pool=1 i ip_addr_obj
cmclient -v ip_addr_obj GETO $IPObject.IPv4Address.[Enable=true]
for i in $ip_addr_obj; do
if [ "$obj" != "$i" ]; then
cmclient -v ip_addr GETV "$i.IPAddress"
cmclient -v subnet GETV "$i.SubnetMask"
help_calc_network ip_bridge_net "$ip_addr" "$subnet"
cmclient -v dhcp_min_addr GETV $dhcp_pool.MinAddress
help_calc_network dhcp_net "$dhcp_min_addr" "$subnet"
if [ "$ip_bridge_net" = "$dhcp_net" ]; then
disable_pool=0
break;
fi
fi
done
[ "$disable_pool" = "1" ] && cmclient SET "$dhcp_pool.Enable false"
}
service_reconf_dhcp() {
local IPObject="${obj%%.IPv4Address*}"
local new_pool_created=0 dhcp_pools
cmclient -v dhcp_pools GETO Device.DHCPv4.Server.Pool.[Interface="$IPObject"]
if [ -n "$oldIPAddress" -a -n "$oldSubnetMask" -a \( "$op" = "d" -o "$changedIPAddress" = "1" -o "$changedSubnetMask" = "1" \) ]; then
if [ "$op" != "d" ]; then
[ "$changedIPAddress" = "1" ] && new_ip=$newIPAddress || cmclient -v new_ip GETV ${obj}.IPAddress
[ "$changedSubnetMask" = "1" ] && new_subnet=$newSubnetMask || cmclient -v new_subnet GETV ${obj}.SubnetMask
help_first_ip new_start_ip "$new_ip" "$new_subnet" dhcp
help_last_ip new_end_ip "$new_ip" "$new_subnet" dhcp
fi
help_calc_network old_network "$oldIPAddress" "$oldSubnetMask"
for dhcp_pool in $dhcp_pools; do
local enablePool
cmclient -v enablePool GETV $dhcp_pool.Enable
cmclient -v dhcp_min_addr GETV $dhcp_pool.MinAddress
help_calc_network dhcp_network "$dhcp_min_addr" "$oldSubnetMask"
[ "$old_network" != "$dhcp_network" ] && continue
cmclient -v dhcp_max_addr GETV $dhcp_pool.MaxAddress
if [ "$op" != "d" ] && \
help_ipcmp_enh "$dhcp_min_addr" ">=" "$new_start_ip" && \
help_ipcmp_enh "$dhcp_max_addr" "<=" "$new_end_ip" ; then
local setm_params
for v in IPRouters DNSServers; do
cmclient -v list GETV $dhcp_pool.$v
if help_is_in_list $list $oldIPAddress; then
list="`help_str_replace $oldIPAddress $newIPAddress $list`"
setm_params="${setm_params:+$setm_params	}$dhcp_pool.$v=$list"
fi
done
setm_params="${setm_params:+$setm_params	}$dhcp_pool.SubnetMask=$new_subnet"
cmclient SETM "$setm_params"
else
local setm_par="" domain_name lease_time
[ "$user" = "GUI_LAN_Settings" ] && continue
[ "$enablePool" != "true" ] && continue
check_and_disable_dhcps "$IPObject" "$dhcp_pool"
if [ "$op" != "d" -a "$new_pool_created" != "1" ]; then
new_dhcp_pool="Device.DHCPv4.Server.Pool.$(cmclient ADD Device.DHCPv4.Server.Pool)"
setm_par="$setm_par${setm_par:+	}$new_dhcp_pool.MinAddress=$new_start_ip"
setm_par="$setm_par	$new_dhcp_pool.MaxAddress=$new_end_ip"
setm_par="$setm_par	$new_dhcp_pool.SubnetMask=$new_subnet"
setm_par="$setm_par	$new_dhcp_pool.IPRouters=$new_ip"
setm_par="$setm_par	$new_dhcp_pool.DNSServers=$new_ip"
cmclient -v domain_name GETV $dhcp_pool.DomainName
setm_par="$setm_par	$new_dhcp_pool.DomainName=$domain_name"
cmclient -v lease_time GETV $dhcp_pool.LeaseTime
setm_par="$setm_par	$new_dhcp_pool.LeaseTime=$lease_time"
setm_par="$setm_par	$new_dhcp_pool.Interface=$IPObject"
setm_par="$setm_par	$new_dhcp_pool.Enable=$enablePool"
new_pool_created=1
fi
[ -n "$setm_par" ] && cmclient SETM "$setm_par"
fi
done
fi
}
service_reconf_ipv4() {
local IPObject="${obj%%.IPv4Address*}" IPInterfaceName IPUpstream new_status addr_deleted IPTable DHCPOpt121Enable \
retVoip \
loopback
cmclient -v loopback GETV ${IPObject}.Loopback
if [ "$loopback" = "true" ]; then
[ -x /etc/ah/helper_loopback.sh ] && ip_loopback_get_if_name IPInterfaceName || exit 0
else
help_lowlayer_ifname_get IPInterfaceName "${IPObject}"
fi
[ ${#IPInterfaceName} -eq 0 ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "Error_Misconfigured" && return 0
cmclient -v IPStatus GETV ${IPObject}.Status
[ "$IPStatus" = "Dormant" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "Disabled" && return 0
IPTable=$((${IPObject##*.} + 1000))
if [ "$user" = "CWMP" ] && [ "$newAddressingType" != "Static" ]; then
[ "$changedIPAddress" = "1" -o "$changedSubnetMask" = "1" ] && exit 8
fi
cmclient -v IPUpstream GETV ${IPObject}.X_ADB_Upstream
if [ -n "$newAddressingType" ]; then
[ "$newAddressingType" = "Static" ] && cmclient SETS "$obj" 1 || cmclient SETS "$obj" 0
fi
[ "$loopback" = "false" ] && service_reconf_dhcp
if [ "$changedEnable" = "1" ]; then
[ "$IPStatus" != "Up" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "Disabled" && return 0
elif [ "$user" != "IPIf" -a "$op" != "d" ]; then
[ "$IPStatus" != "Up" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "Disabled" && return 0
if [ ${#oldSubnetMask} -ne 0 -a "$changedSubnetMask" = "1" -a ${#oldIPAddress} -ne 0 -a "$changedIPAddress" = "1" ]; then
ip addr del $oldIPAddress/$oldSubnetMask dev $IPInterfaceName
[ "$loopback" = true -a -x /etc/ah/helper_loopback.sh ] && ip_loopback_set_dummy
addr_deleted="$oldIPAddress"
help_calc_network networkAddress ${oldIPAddress} ${oldSubnetMask}
ip route del ${networkAddress#*=}/$oldSubnetMask dev $IPInterfaceName table $IPTable
elif [ ${#oldSubnetMask} -ne 0 -a "$changedSubnetMask" = "1" ]; then
ip addr del $newIPAddress/$oldSubnetMask dev $IPInterfaceName
[ "$loopback" = true -a -x /etc/ah/helper_loopback.sh ] && ip_loopback_set_dummy
addr_deleted="$newIPAddress"
help_calc_network networkAddress ${newIPAddress} ${oldSubnetMask}
ip route del ${networkAddress#*=}/$oldSubnetMask dev $IPInterfaceName table $IPTable
elif [ ${#oldIPAddress} -ne 0 -a "$changedIPAddress" = "1" ]; then
ip addr del $oldIPAddress/$newSubnetMask dev $IPInterfaceName
[ "$loopback" = true -a -x /etc/ah/helper_loopback.sh ] && ip_loopback_set_dummy
addr_deleted="$oldIPAddress"
help_calc_network networkAddress ${oldIPAddress} ${newSubnetMask}
ip route del ${networkAddress#*=}/$newSubnetMask dev $IPInterfaceName table $IPTable
fi
[ -f /etc/ah/IPv6rd.sh -a -n "$addr_deleted" ] && \
cmclient -u "${AH_NAME}${addr_deleted}" SET "Device.IPv6rd.[Enable=true].InterfaceSetting.[Enable=true].[AddressSource=${obj}].Enable" true
fi
if [ -d "/sys/class/net/${IPInterfaceName}" ]; then
help_calc_network networkAddress ${newIPAddress} ${newSubnetMask}
if [ "$op" != "d" -a "$IPStatus" = "Up" -a "$newEnable" = "true" ]; then
help_calc_broadcast broadcastAddress ${newIPAddress} ${newSubnetMask}
ip addr add $newIPAddress/$newSubnetMask broadcast ${broadcastAddress#*=} dev $IPInterfaceName
[ "$loopback" = true -a -x /etc/ah/helper_loopback.sh ] && ip_loopback_set_dummy
IFS=. read _t _ <  /proc/uptime
cmclient SETE "${obj}.X_ADB_StartTime" "$_t"
[ "$newSubnetMask" != "255.255.255.255" ] &&\
ip route add ${networkAddress#*=}/$newSubnetMask dev $IPInterfaceName table $IPTable
if [ "$user" != "IPIf" ]; then
cmclient -v DHCPOpt121Enable GETV "$IPObject.X_ADB_DHCPOpt121Enable"
if [ "$DHCPOpt121Enable" = "true" ]; then
cmclient SET "Device.Routing.Router.1.IPv4Forwarding.[Interface=${IPObject}].[Enable=true].Enable" true
cmclient SET "Device.Routing.Router.1.IPv4Forwarding.[Interface=${IPObject}].[Enable=false].Enable" false
else
cmclient SET "Device.Routing.Router.1.IPv4Forwarding.[Interface=${IPObject}].[Enable=false].Enable" false
fi
fi
if [ "$IPUpstream" = "false" ]; then
case "$IPInterfaceName" in "br"*)
arping -q -c 2 -U -I $IPInterfaceName -s $newIPAddress ${broadcastAddress#*=} &
;; esac
if [ "$changedIPAddress" = "1" -o "$changedEnable" = "1" ]; then
/etc/ah/BridgingBridge.sh refreshlanrouting &
cmclient SET "Device.Services.X_ADB_IGMPProxy.[Enable=true].Refresh" true
fi
fi
new_status="Enabled"
else
ip addr del $newIPAddress/$newSubnetMask dev $IPInterfaceName
[ "$loopback" = true -a -x /etc/ah/helper_loopback.sh ] && ip_loopback_set_dummy
[ "$op" != "d" ] && cmclient -u ${AH_NAME}${obj} SET "${obj}.X_ADB_StartTime" 0
[ "$newSubnetMask" != "255.255.255.255" ] &&\
ip route del ${networkAddress#*=}/$newSubnetMask dev $IPInterfaceName table $IPTable
new_status="Disabled"
fi
if [ -f /etc/ah/IPv6rd.sh -a "$user" != "IPIf" ]; then
local tobj tcmd='' setm_ipv6=''
cmclient -v tobj GETO "Device.IPv6rd.[Enable=true].InterfaceSetting.[Enable=true].[TunneledInterface=${obj%%.IPv4Address*}]"
if [ ${#tobj} -gt 0 ]; then
if [ "$op" = "s" -a "$changedIPAddress" = "1" -a ${#newIPAddress} -gt 0 ]; then
tcmd="add"
elif [ "$op" = "d" -a ${#oldIPAddress} -gt 0 ]; then
tcmd="del${oldIPAddress}"
fi
if [ ${#tcmd} -gt 0 ]; then
for tobj in $tobj; do
setm_ipv6="${setm_ipv6:+$setm_ipv6	}${tobj}.Enable=true	${tobj}.AddressSource=${obj}"
done
[ ${#setm_ipv6} -ne 0 ] && cmclient -u "${AH_NAME}${tcmd}" SETM "$setm_ipv6"
fi
fi
fi
if [ -f /etc/ah/VoIPNetwork.sh ]; then
if iptables -t nat -L NATIpPhone | grep -q IP_PHONE_"$IPInterfaceName"; then
help_iptables -t nat -D NATIpPhone -j IP_PHONE_"$IPInterfaceName"
help_iptables -t nat -F IP_PHONE_"$IPInterfaceName"
help_iptables -t nat -X IP_PHONE_"$IPInterfaceName"
fi
local nonMasqNAT nonMasqNAPT
cmclient -v nonMasqNAT GETO Device.NAT.InterfaceSetting.[Enable=true].[X_ADB_ExternalIPAddress!]
cmclient -v nonMasqNAPT GETO Device.NAT.InterfaceSetting.[Enable=true].[X_ADB_ExternalPort!0]
cmclient -v SIPPort GETV Device.Services.VoiceService.1.X_ADB_SIP.LocalPort
if [ -z "$nonMasqNAT" -a -z "$nonMasqNAPT" -a "$IPUpstream" = "false" -a -n "$SIPPort" -a -n "$newSubnetMask" ]; then
help_iptables -t nat -N IP_PHONE_"$IPInterfaceName"
if [ "$newEnable" = "true" -a  "$op" != "d" ]; then
help_iptables -t nat -A IP_PHONE_"$IPInterfaceName" -s ${networkAddress#*=}/$newSubnetMask ! -d ${networkAddress#*=}/$newSubnetMask -p udp --sport "$SIPPort" -j MASQUERADE --to-ports 49152-65535
help_iptables -t nat -A IP_PHONE_"$IPInterfaceName" -s ${networkAddress#*=}/$newSubnetMask ! -d ${networkAddress#*=}/$newSubnetMask -p udp --dport 5060 -m multiport ! --sports "$SIPPort$skip_src_ports" -j MASQUERADE --to-ports 49152-65535
cmclient -v retVoip GETO "Services.VoiceService.[X_ADB_Enable=true].VoiceProfile.[Enable=Enabled].Line.[Enable=Enabled]"
[ -z "$retVoip" ] && help_iptables -t nat -I IP_PHONE_"$IPInterfaceName" -j RETURN
help_iptables -t nat -A NATIpPhone -j IP_PHONE_"$IPInterfaceName"
fi
fi
local ip_ppp
cmclient -v ip_ppp GETO "$IPObject.[LowerLayers>Device.PPP.Interface]"
[ "$user" != "IPIf" -a -z "$ip_ppp" ] && /etc/ah/VoIPNetwork.sh u "$IPObject" &
fi
[ "$op" != "d" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "$new_status"
else
[ "$op" != "d" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "Error_Misconfigured"
return 0
fi
}
case "$op" in
a)
/etc/ah/BridgingBridge.sh refreshlanrouting
;;
s)
if [ "$changedIPAddress" = "1" -a -n "$newIPAddress" ]; then
cmclient -v is_no_upstream GETO "Device.IP.Interface.*.[X_ADB_Upstream=false].IPv4Address.[IPAddress=$newIPAddress].[Loopback=false]"
if [ ${#is_no_upstream} -ne 0 ]; then
[ ${#newSubnetMask} -ne 0 ] && mask="$newSubnetMask" || cmclient -v mask GETV "$obj".SubnetMask
help_mask2cidr prefix ${mask}
help_lowlayer_ifname_get ifname "$obj"
/etc/ah/Firewall.sh ifchange "$obj"
logger -t "cm" -p 7 "LAN IP Interfce ${ifname} changed to $newIPAddress/$prefix"
fi
fi
[ "$changedEnable" = "0" -a "$newEnable" = "false" ] && exit 0
service_reconf_ipv4
;;
g)
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
;;
d)
[ "$oldEnable" = "false" -o -z "$oldIPAddress" -o -z "$oldSubnetMask" ] && exit 0
service_reconf_ipv4
;;
esac
exit 0
