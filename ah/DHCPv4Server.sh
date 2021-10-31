#!/bin/sh
AH_NAME="DHCPv4Server"
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize "$AH_NAME"
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_svc.sh
. /etc/ah/helper_ipcalc.sh
dhcpsPIDFile="/var/run/dhcps.pid"
check_dhcp_common() {
local p v
cmclient -v ifp GETV "$i".Interface
ifn=""
[ -n "$ifp" ] || return 1
cmclient -v ifn GETV "%($ifp.LowerLayers).Name"
[ -n "$ifn" ] || return 1
for p in Chaddr ChaddrMask; do
cmclient -v v GETV "$i.$p"
[ -n "$v" ] && ! help_is_valid_mac "$v" && return 1
done
return 0
}
check_dhcp_server() {
local i=$1 p v j minAddress maxAddress subnetMask yiAddr chAddr netaForMin netaForMax brdcst
check_dhcp_common || return 1
cmclient -v minAddress GETV "$i.MinAddress"
cmclient -v maxAddress GETV "$i.MaxAddress"
cmclient -v subnetMask GETV "$i.SubnetMask"
help_is_valid_ip "$subnetMask" || return 1
help_ipcmp "$minAddress" "$maxAddress"
[ $? -eq 1 -o $? -eq 255 ] && return 1
help_calc_network netaForMin "$minAddress" "$subnetMask"
help_calc_network netaForMax "$maxAddress" "$subnetMask"
[ "$netaForMin" = "$netaForMax" ] || return 1
[ "$minAddress" = "$netaForMin" ] && return 1
help_calc_broadcast brdcst "$minAddress" "$subnetMask"
[ "$brdcst" = "$maxAddress" ] && return 1
for p in ReservedAddresses DNSServers IPRouters; do
cmclient -v v GETV "$i.$p"
set -f
IFS=,
set -- $v
unset IFS
set +f
for v; do
help_is_valid_ip "$v" || return 1
done
done
cmclient -v p GETO "$i".StaticAddress.[Enable=true]
for p in $p; do
cmclient -v yiAddr GETV "$p.Yiaddr"
cmclient -v chAddr GETV "$p.Chaddr"
help_is_valid_ip "$yiAddr" || return 1
help_ipcmp "$yiAddr" "$maxAddress"
[ $? -eq 1 -o $? -eq 255 ] && return 1
help_ipcmp "$minAddress" "$yiAddr"
[ $? -eq 1 -o $? -eq 255 ] && return 1
help_is_valid_mac "$chAddr" || return 1
cmclient -v chaddrs GETO "$p".[Chaddr=${chAddr}]
cnt=0
for j in $chaddrs; do
cnt=$((cnt + 1))
done
[ $cnt -eq 1 ] || return 1
done
return 0
}
check_dhcp_relay() {
local ifoutp p v
ifoutn=""
ifoutnat=""
check_dhcp_common || return 1
cmclient -v v GETV "$i".LocallyServed
if [ "$v" != "true" ]; then
cmclient -v v GETV "$i".DHCPServerIPAddress
help_is_valid_ip "$v" || return 1
cmclient -v ifoutp GETV "$i".X_ADB_UpstreamInterface
[ -n "$ifoutp" ] || return 1
cmclient -v ifoutn GETV "%(${ifoutp}.LowerLayers).Name"
[ -n "$ifoutn" ] || return 1
cmclient -v ifoutnat GETO Device.NAT.InterfaceSetting.[Interface=${ifoutp}].[Status=Enabled]
fi
return 0
}
getType() {
if [ "$1" = "Hex" ]; then
echo "hex"
elif [ "$1" = "String" ]; then
echo "string"
elif [ "$1" = "Empty" ]; then
echo "empty"
elif [ "$1" = "Boolean" ]; then
echo "bool"
elif [ "$1" = "IPAddress" ]; then
echo "ip"
elif [ "$1" = "IPAddressList" ]; then
echo "ip"
elif [ "$1" = "U8" ]; then
echo "u8"
elif [ "$1" = "U16" ]; then
echo "u16"
elif [ "$1" = "U32" ]; then
echo "u32"
elif [ "$1" = "S8" ]; then
echo "s8"
elif [ "$1" = "S16" ]; then
echo "s16"
elif [ "$1" = "S32" ]; then
echo "s32"
fi
}
configure_lease() {
local type mac ip_addr lease good_ip l i v t
cmclient -v l GETO $1.Client
for l in $l; do
cmclient -v mac GETV $l.Chaddr
if ! help_is_valid_mac "$mac"; then
cmclient DEL $l >/dev/null
echo "The host with invalid mac ($mac) has been removed!" >/dev/console
logger -t cm -p 3 "The host with invalid mac ($mac) has been removed!"
continue
fi
good_ip=0
cmclient -v i GETO "$l".IPv4Address
for i in $i; do
cmclient -v ip_addr GETV $i.IPAddress
if help_is_valid_ip "$ip_addr"; then
cmclient -v lease GETV $i.X_ADB_LeaseTimeRemaining
lease="	lease $ip_addr $lease"
good_ip=1
else
cmclient DEL $i >/dev/null
logger -t cm -p 3 "The host with mac $mac has invalid IP address. IP Removed!"
continue
fi
done
if [ $good_ip -eq 1 ]; then
echo "client $mac"
echo "$lease"
else
cmclient DEL $l >/dev/null
logger -t cm -p 3 "The host with mac $mac has no IP address. Host removed!"
continue
fi
cmclient -v o GETO "$l".Option
for o in $o; do
cmclient -v type GETV $o.X_ADB_Type
if [ "$type" = "Undefined" ]; then
cmclient DEL $o >/dev/null
cmclient -v o GETV $l.Chaddr
logger -t cm -p 3 "The host with mac $o had an invalid option!"
continue
fi
cmclient -v t GETV $o.Tag
cmclient -v v GETV $o.Value
echo "	option `getType "$type"` $t $v"
done
done
}
find_cpe_ip_addr_for_pool () {
local cpeAddr
cmclient -v poolMinAddr GETV "$i.MinAddress"
cmclient -v poolMaxAddr GETV "$i.MaxAddress"
cmclient -v poolSubMask GETV "$i.SubnetMask"
cmclient -v cpeIpAddrs GETO "$ifp.IPv4Address.[Enable=true].[AddressingType=Static]"
dhcp_network=`help_calc_network "$poolMinAddr" "$poolSubMask"`
is_ip_in_subnet $poolMaxAddr $dhcp_network $poolSubMask || return 1
for _cpeIpAddr in $cpeIpAddrs; do
cmclient -v cpeSubMask GETV "$_cpeIpAddr.SubnetMask"
cmclient -v cpeAddr GETV "$_cpeIpAddr.IPAddress"
cpe_network=`help_calc_network "$cpeAddr" "$cpeSubMask"`
if help_ipcmp_enh "$cpeSubMask" "<=" "$poolSubMask" ; then
if is_ip_in_subnet $cpeAddr $dhcp_network $poolSubMask ; then
interface_addr="$cpeAddr"
return 0
fi
else
if is_ip_in_subnet $poolMinAddr $cpe_network $cpeSubMask && is_ip_in_subnet $poolMaxAddr $cpe_network $cpeSubMask; then
interface_addr="$cpeAddr"
return 0
fi
fi
done
return 1
}
create_dhcps_config_file()  {
local ret=1 v o i
{
[ "$user" = "boot" ] && rm -f /tmp/dhcps-leases.bin
echo "leases /tmp/dhcps-leases.bin"
help_iptables -F DHCPServices
cmclient -v v GETV Device.DHCPv4.Server.Enable
if [ "$v" = "true" ]; then
echo "server on"
local adr
cmclient -v i GETO Device.DHCPv4.Server.Pool
for i in $i; do
[ "$op" = "d" -a "$i" = "$obj" ] && continue
cmclient -v v GETV "$i".Enable
if [ "$v" = "false" ]; then
cmclient SETE "$i".Status Disabled >/dev/null
continue
fi
if ! check_dhcp_server "$i"; then
cmclient SETE "$i".Status Error_Misconfigured >/dev/null
continue
fi
if ! find_cpe_ip_addr_for_pool ; then
cmclient SETE "$i".Status Error_Misconfigured >/dev/console
continue
fi
ret=0
cmclient SETE "$i".Status Enabled >/dev/null
cmclient -v v GETV "$i".Order
echo "pool "$i"	$v"
echo "interface $ifn"
echo "interface_addr $interface_addr"
cmclient -v ifaddr GETV $ifp.IPv4Address.[Enable=true].[AddressingType=Static].IPAddress
for _ifaddr in $ifaddr; do
ifaddr=$_ifaddr
break
done
[ -n "$ifaddr" ] && echo "nextserver $ifaddr"
help_iptables -A DHCPServices -i $ifn -p udp -m multiport --dports 67:68 -j ACCEPT
echo "start ${poolMinAddr}"
echo "end ${poolMaxAddr}"
cmclient -v reserved GETV "$i".ReservedAddresses
for _ipAddr in $cpeIpAddrs; do
cmclient -v adr GETV "$_ipAddr.IPAddress"
if help_ipcmp_enh "$adr" ">=" "$poolMinAddr" && \
help_ipcmp_enh "$adr" "<=" "$poolMaxAddr" ; then
if [ -n "$reserved" ]; then
if ! help_is_in_list "$reserved" "$adr"; then
reserved="$reserved,${adr}"
fi
else
reserved="$adr"
fi
fi
done
[ -n "$reserved" ] && echo "reserved $reserved"
cmclient -v vendorId GETV "$i".VendorClassID
if [ -n "$vendorId" ]; then
buf="option"
cmclient -v v GETV "$i".VendorClassIDExclude
[ "$v" = "true" ] && buf="$buf no"
cmclient -v vendorIDMode GETV "$i".VendorClassIDMode
case "$vendorIDMode" in
"Exact") buf="$buf match" ;;
"Prefix") buf="$buf prefix" ;;
"Suffix") buf="$buf suffix" ;;
"Substring") buf="$buf substr" ;;
esac
buf="$buf string 60 $vendorId"
echo "$buf"
fi
cmclient -v clientId GETV "$i".ClientID
if [ -n "$clientId" ]; then
buf="option"
cmclient -v v GETV "$i".ClientIDExclude
[ "$v" = "true" ] && buf="$buf no"
buf="$buf match hex 61 $clientId"
echo "$buf"
fi
cmclient -v classId GETV "$i".UserClassID
if [ -n "$classId" ]; then
buf="option"
cmclient -v v GETV "$i".UserClassIDExclude
[ "$v" = "true" ] && buf="$buf no"
buf="$buf match hex 77 $classId"
echo "$buf"
fi
cmclient -v chaddr GETV "$i".Chaddr
if [ -n "$chaddr" ]; then
buf="mac"
cmclient -v v GETV "$i".ChaddrExclude
[ "$v" = "true" ] && buf="$buf no"
cmclient -v v GETV "$i".ChaddrMask
buf="$buf $v $chaddr"
echo "$buf"
fi
echo "subnet ${poolSubMask}"
cmclient -v dns GETV "$i".DNSServers
if [ -n "$dns" ]; then
echo "dns $dns"
fi
cmclient -v routers GETV "$i".IPRouters
if [ -n "$routers" ]; then
echo "router $routers"
fi
cmclient -v domain GETV "$i".DomainName
if [ -n "$domain" ]; then
echo "option send string 15 $domain"
fi
cmclient -v v GETV "$i".LeaseTime
echo "leasetime $v"
cmclient -v probe GETV "$i".X_ADB_AddressProbe
case "$probe" in
"None")
echo "probe none"
echo "offertime 30"
;;
"ARP Cache")
echo "probe arp"
echo "offertime 30"
;;
"ARP Request")
echo "probe arpreq"
cmclient -v probedelay GETV "$i".X_ADB_AddressProbeDelay
echo "probe_delay $probedelay"
echo "offertime $((16 + $probedelay / 1000))"
;;
esac
cmclient -v v GETV "$i".X_ADB_AutoConfDisable
[ "$v" = "true" ] && echo "no_autoconf on"
cmclient -v v GETV "$i".X_ADB_UseStaticAddressAsFilter
[ "$v" = "true" ] && echo "use_static_as_filter true"
cmclient -v s GETO "$i".StaticAddress.[Enable=true]
for s in $s; do
cmclient -v cha GETV "$s".Chaddr
cha=$(help_lowercase $cha)
cmclient -v yad GETV "$s".Yiaddr
cmclient -v dup GETO "$i".Client.[Chaddr!$cha].IPv4Address.[IPAddress="$yad"]
dup_=${dup%.IPv4Address.*}
if [ "$op" = "d" ]; then
if [ "$obj" != "$s" ];then
echo "static $cha $yad"
[ -n "$dup_" ] && cmclient DEL $dup_ >/dev/null
fi
else
echo "static $cha $yad"
[ -n "$dup_" ] && cmclient DEL $dup_ >/dev/null
fi
done
cmclient -v o GETO "$i".Option.[Enable=true]
for o in $o; do
subopt=""
suboptBuf=""
optBuf=""
cmclient -v tag GETV "$o".Tag
cmclient -v optVal GETV "$o".Value
[ -z "$optVal" ] && continue
cmclient -v subopt GETO "$o".X_ADB_SubOption.[Enable=true]
for subopt in $subopt; do
cmclient -v suboptTag GETV "$subopt".Tag
suboptTag=`printf %02X $suboptTag`
cmclient -v suboptValue GETV "$subopt".Value
if [ -z "$suboptValue" ]; then
cmclient -v suboptReference GETV "$subopt".Reference
cmclient -v suboptValue GETV $suboptReference
fi
suboptLen=`printf %02X ${#suboptValue}`
suboptBuf=$suboptBuf$suboptTag$suboptLen`echo -n "$suboptValue" | hexdump -ve '/1 "%02X"'`
done
if [ -z "$suboptBuf" ]; then
cmclient -v optBuf GETV "$o".Value
else
suboptLen=$((${#suboptBuf} / 2))
suboptLen=`printf %02X $suboptLen`
suboptBuf=$val$suboptLen$suboptBuf
optBuf="$optBuf$optVal$suboptBuf"
fi
cmclient -v type GETV "$o".X_ADB_Type
cmclient -v sendMode GETV "$o".X_ADB_OnRequest
[ "$sendMode" = "true" ] && sendMode="set" || sendMode="send"
cmclient -v v GETV "$o".Tag
if [ -z "$type" -o "$type" = "Hex" ]; then
echo "option ${sendMode} hex $v $optBuf"
elif [ "$type" = "String" ]; then
echo "option ${sendMode} string $v $optBuf"
elif [ "$type" = "Empty" ]; then
echo "option ${sendMode} empty $v"
elif [ "$type" = "Boolean" ]; then
echo "option ${sendMode} bool $v $optBuf"
elif [ "$type" = "IPAddress" ]; then
echo "option ${sendMode} ip $v $optBuf"
elif [ "$type" = "IPAddressList" ]; then
echo "option ${sendMode} ip $v $optBuf"
elif [ "$type" = "U8" ]; then
echo "option ${sendMode} u8 $v $optBuf"
elif [ "$type" = "U16" ]; then
echo "option ${sendMode} u16 $v $optBuf"
elif [ "$type" = "U32" ]; then
echo "option ${sendMode} u32 $v $optBuf"
elif [ "$type" = "S8" ]; then
echo "option ${sendMode} s8 $v $optBuf"
elif [ "$type" = "S16" ]; then
echo "option ${sendMode} s16 $v $optBuf"
elif [ "$type" = "S32" ]; then
echo "option ${sendMode} s32 $v $optBuf"
fi
done
[ "$user" = "boot" ] && configure_lease "$i"
done
else
echo "server off"
fi
cmclient -v v GETV Device.DHCPv4.Relay.Enable
if [ "$v" = "true" ]; then
echo "relay on"
cmclient -v i GETO Device.DHCPv4.Relay.Forwarding
for i in $i; do
[ "$op" = "d" -a "$i" = "$obj" ] && continue
cmclient -v v GETV "$i".Enable
if [ "$v" = "false" ]; then
cmclient SETE "$i".Status Disabled >/dev/null
continue
fi
if ! check_dhcp_relay "$i"; then
cmclient SETE "$i".Status Error_Misconfigured >/dev/null
continue
fi
ret=0
cmclient SETE "$i".Status Enabled >/dev/null
cmclient -v v GETV "$i".Alias
cmclient -v o GETV "$i".Order
echo "relay_pool $v	$o"
echo "interface $ifn"
[ -n "$ifoutn" ] && echo "interface_out $ifoutn"
[ -n "$ifoutnat" ] && echo "nat"
cmclient -v vendorId GETV "$i".VendorClassID
if [ -n "$vendorId" ]; then
buf="option"
cmclient -v v GETV "$i".VendorClassIDExclude
[ "%v" = "true" ] && buf="$buf no"
cmclient -v v GETV "$i".VendorClassIDMode
if [ "$v" = "Exact" ]; then
buf="$buf match"
elif [ "$v" = "Prefix" ]; then
buf="$buf prefix"
elif [ "$v" = "Suffix" ]; then
buf="$buf suffix"
elif [ "$v" = "Substring" ]; then
buf="$buf substr"
fi
buf="$buf string 60 $vendorId"
echo "$buf"
fi
cmclient -v clientId GETV "$i".ClientID
if [ -n "$clientId" ]; then
buf="option"
cmclient -v v GETV "$i".ClientIDExclude
[ "$v" = "true" ] && buf="$buf no"
buf="$buf match hex 61 $clientId"
echo "$buf"
fi
cmclient -v classId GETV "$i".UserClassID
if [ -n "$classId" ]; then
buf="option"
cmclient -v v GETV "$i".UserClassIDExclude
[ "$v" = "true" ] && buf="$buf no"
buf="$buf match hex 77 $classId"
echo "$buf"
fi
cmclient -v chaddr GETV "$i".Chaddr
if [ -n "$chaddr" ]; then
buf="mac"
cmclient -v v GETV "$i".ChaddrExclude
[ "$v" = "true" ] && buf="$buf no"
cmclient -v v GETV "$i".ChaddrMask
buf="$buf $chaddr $v"
echo "$buf"
fi
cmclient -v v GETV "$i".LocallyServed
if [ "$v" = "true" ]; then
echo "local on"
else
cmclient -v v GETV "$i".DHCPServerIPAddress
echo "dhcpserver $v"
fi
done
else
echo "relay off"
fi
} >/tmp/dhcps.conf
return $ret
}
dhcps_signal_daemon() {
local signal="$1" dhcps_pid
if [ -f "$dhcpsPIDFile" ]; then
read dhcps_pid < $dhcpsPIDFile
if [ -n "$dhcps_pid" ]; then
if ! help_svc_proc_pid "$dhcps_pid" 'dhcps'; then
dhcps_pid=''
rm -f "$dhcpsPIDFile"
killall dhcps
return 1
fi
fi
if [ -n "$dhcps_pid" ]; then
echo "### $AH_NAME: Executing <kill "-$signal $dhcps_pid"> ###"
kill -$signal $dhcps_pid
return 0
fi
fi
return 1
}
restart_dhcps_process() {
if create_dhcps_config_file; then
if ! dhcps_signal_daemon "SIGHUP" ; then
help_svc_start 'dhcps /tmp/dhcps.conf' '' '' '' '' '15'
help_svc_wait_proc_started dhcps "$dhcpsPIDFile" 30
fi
else
help_svc_stop dhcps "$dhcpsPIDFile" 15
fi
}
service_add() {
case "$obj" in
Device.DHCPv4.Server.Pool.*.Option.*)
;;
Device.DHCPv4.Server.Pool.*|Device.DHCPv4.Relay.Forwarding.*)
local maxorder=0 i
cmclient -v i GETV "${obj%.*}.*.Order"
for i in $i; do
[ $i -gt $maxorder ] && maxorder=$i
done
maxorder=$((maxorder + 1))
cmclient SETE "$obj".Order $maxorder
;;
esac
}
service_delete() {
case "$obj" in
Device.DHCPv4.Server.Pool.*.Option.*)
cmclient SETE "$obj.Enable false"
;;
Device.DHCPv4.Server.Pool.*|Device.DHCPv4.Relay.Forwarding.*)
cmclient -v i GETO "${obj%.*}.*.[Order+$oldOrder]"
for i in $i; do
cmclient -v order GETV "$i".Order
cmclient SETE "$i.Order" "$((order - 1))"
done
;;
esac
cmclient -v dhcps_enable GETV "Device.DHCPv4.Server.Enable"
cmclient -v dhcpr_enable GETV "Device.DHCPv4.Relay.Enable"
[ "$dhcps_enable" = "true" -o "$dhcpr_enable" = "true" ] && restart_dhcps_process
}
service_config() {
case "$obj" in
Device.DHCPv4.Server)
restart_dhcps_process
if [ $changedEnable -eq 1 ]; then
local state="enabled"
if [ "$newEnable" = "false" ]; then
state="disabled"
cmclient SETE "Device.DHCPv4.Server.Pool.[Status!Disabled].Status" Disabled
fi
logger -t "cm" -p 3 "LAN: DHCP server ${state}"
fi
;;
Device.DHCPv4.Relay)
restart_dhcps_process
if [ $changedEnable -eq 1 ]; then
local state="Enabled"
if [ "$newEnable" = "false" ]; then
state="Disabled"
cmclient SETE "Device.DHCPv4.Relay.Forwarding.[Status!Disabled].Status" Disabled
fi
cmclient SETE "${obj}.Status ${state}"
logger -t "cm" -p 3 "LAN: DHCP relay ${state}"
fi
;;
Device.DHCPv4.Server.Pool.*.Option.*)
cmclient -v dhcps_enable GETV "Device.DHCPv4.Server.Enable"
cmclient -v dhcpr_enable GETV "Device.DHCPv4.Relay.Enable"
[ "$dhcps_enable" = "true" -o "$dhcpr_enable" = "true" ] && restart_dhcps_process
;;
Device.DHCPv4.Server.Pool.*.StaticAddress.*)
cmclient -v dhcps_enable GETV "Device.DHCPv4.Server.Enable"
[ "$dhcps_enable" = "true" -a "$newEnable" = "true" ] && restart_dhcps_process
;;
Device.DHCPv4.Server.Pool.*|Device.DHCPv4.Relay.Forwarding.*)
[ $changedOrder -eq 1 ] && help_sort_orders "$obj" "$oldOrder" "$newOrder" "$AH_NAME"
if [ "$changedMaxAddress" = "1" -o "$changedMinAddress" = "1" ]; then
logger -t "cm" -p 5 "LAN: DHCP server – change range ${newMinAddress} ${newMaxAddress}"
fi
cmclient -v dhcps_enable GETV "Device.DHCPv4.Server.Enable"
cmclient -v dhcpr_enable GETV "Device.DHCPv4.Relay.Enable"
[ "$dhcps_enable" = "true" -o "$dhcpr_enable" = "true" ] && restart_dhcps_process
;;
esac
}
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
