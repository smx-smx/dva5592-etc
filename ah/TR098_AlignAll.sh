#!/bin/sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
bridged_wlan_list=""
bridged_lan_list=""
lan_index=""
wan_index=""
help98_add_dhcp_options() {
local tr181_dhcp="$1"
local tr098_dhcp="$2"
for option in `cmclient GETO "$tr181_dhcp.Option"`
do
opt_id=`help181_add_tr98obj "$tr098_dhcp.DHCPOption" "$option"`
cmclient -u "DHCPv4Server" SET "$option.$PARAM_TR098" "$tr098_dhcp.DHCPOption.$opt_id"
done
for static_addr in `cmclient GETO "$tr181_dhcp.StaticAddress"`
do
addr_id=`help181_add_tr98obj "$tr098_dhcp.DHCPStaticAddress" "$static_addr"`
cmclient -u "DHCPv4Server" SET "$static_addr.$PARAM_TR098" "$tr098_dhcp.DHCPStaticAddress.$addr_id"
done
}
help98_build_lan_ipinterface() {
local ipif="$1"
local lan_id="$2"
cmclient SET "$ipif.$PARAM_TR098" "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement"
eth_link=`cmclient GETV "$ipif.LowerLayers"`
cmclient SET "$eth_link.$PARAM_TR098" "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement"
for ipv4 in `cmclient GETO "$ipif.IPv4Address"`
do
ip_id=`help181_add_tr98obj "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement.IPInterface" "$ipv4"`
cmclient -u "IPIfIPv4$ipv4" SET "$ipv4.$PARAM_TR098" "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement.IPInterface.$ip_id"
done
first_pool=1
for dhcp in `cmclient GETO "Device.DHCPv4.Server.Pool.*.[Interface=$ipif]"`
do
if [ "$first_pool" -eq 1 ]; then
cmclient -u "DHCPv4Server" SET "$dhcp.$PARAM_TR098" "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement"
first_pool=0
help98_add_dhcp_options "$dhcp" "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement"
cmclient SET "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement.X_ADB_TR181Name $dhcp" > /dev/null
else
pool_id=`help181_add_tr98obj "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement.DHCPConditionalServingPool" "$dhcp"`
cmclient -u "DHCPv4Server" SET "$dhcp.$PARAM_TR098" "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement.DHCPConditionalServingPool.$pool_id"
help98_add_dhcp_options "$dhcp" "$OBJ_IGD.LANDevice.$lan_id.LANHostConfigManagement.DHCPConditionalServingPool.$pool_id"
fi
done
}
help98_add_portmap() {
local _obj="$1"
local _tr098obj="$2"
for port_map in `cmclient GETO "Device.NAT.PortMapping.*.[Interface=$_obj]"`
do
portId=`help181_add_tr98obj "$_tr098obj.PortMapping" "$port_map"`
cmclient SET "$port_map.$PARAM_TR098" "$_tr098obj.PortMapping.$portId"
done
}
help98_add_dhcpclient() {
local ip_obj="$1"
local wan98="$2"
dhcp=`cmclient GETO "Device.DHCPv4.Client.*.[Interface=$ip_obj]"`
if [ -n "$dhcp" ]; then
cmclient -u "DHCPv4Client" SET "$dhcp.$PARAM_TR098" "$wan98"
for req_opt in `cmclient GETO "$dhcp.ReqOption"`
do
optId=`help181_add_tr98obj "$wan98.DHCPClient.ReqDHCPOption" "$req_opt"`
cmclient -u "DHCPv4Client" SET "$req_opt.$PARAM_TR098" "$wan98.DHCPClient.ReqDHCPOption.$optId"
done
for sent_opt in `cmclient GETO "$dhcp.SentOption"`
do
optId=`help181_add_tr98obj "$wan98.DHCPClient.SentDHCPOption" "$sent_opt"`
cmclient -u "DHCPv4Client" SET "$sent_opt.$PARAM_TR098" "$wan98.DHCPClient.SentDHCPOption.$optId"
done
fi
}
help98_add_wan_ipv4addr() {
local ipif="$1"
local tr098ip="$2"
for ipv4 in `cmclient GETO "$ipif.IPv4Address"`
do
cmclient -u "IPIfIPv4$ipv4" SET "$ipv4.$PARAM_TR098" "$tr098ip"
done
}
help98_build_wan_ip_ppp() {
local _obj="$1" _connObj="$2" _user="$3" _linkObj="$4" ip_obj="" ppp_obj=""
cmclient -v ip_obj GETO "Device.IP.Interface.*.[LowerLayers>$_obj]"
if [ -n "$ip_obj" ]; then
l2tp_obj=`cmclient GETO "Device.X_ADB_VPN.Client.L2TP.*.[Interface=$ip_obj]"`
if [ -n "$l2tp_obj" ]; then
wanppp_obj="$_connObj.WANPPPConnection"
l2tp_ip_obj=`cmclient GETO "Device.IP.Interface.*.[LowerLayers=$l2tp_obj]"`
wanId=`help181_add_tr98obj "$wanppp_obj" "$l2tp_obj" "$wan_index"`
[ -n "$wan_index" ] && wan_index=$(($wan_index+1))
cmclient -u "WANPPPConnection" SET "$wanppp_obj.$wanId.X_ADB_TR181_IPName" "$l2tp_ip_obj"
cmclient -u "PPPIf$l2tp_obj" SET "$l2tp_obj.$PARAM_TR098" "$wanppp_obj.$wanId"
cmclient -u "IPIf$l2tp_ip_obj" SET "$l2tp_ip_obj.$PARAM_TR098" "$wanppp_obj.$wanId"
help98_add_wan_ipv4addr "$l2tp_ip_obj" "$wanppp_obj.$wanId"
help98_add_portmap "$l2tp_ip_obj" "$wanppp_obj.$wanId"
fi
wanip_obj="$_connObj.WANIPConnection"
wanId=`help181_add_tr98obj "$wanip_obj" "$ip_obj" "$wan_index"`
[ -n "$wan_index" ] && wan_index=$(($wan_index+1))
if [ "$_user" = "EthernetLink" ]; then
cmclient -u "EthernetLink$_obj" SET "$_obj.$PARAM_TR098" "$_connObj.$_linkObj"
fi
cmclient -u "IPIf$ip_obj" SET "$ip_obj.$PARAM_TR098" "$wanip_obj.$wanId"
help98_add_wan_ipv4addr "$ip_obj" "$wanip_obj.$wanId"
help98_add_dhcpclient "$ip_obj" "$wanip_obj.$wanId"
help98_add_portmap "$ip_obj" "$wanip_obj.$wanId"
else
cmclient -v ppp_obj GETO "Device.PPP.Interface.*.[LowerLayers>$_obj]"
if [ -n "$ppp_obj" ]; then
wanppp_obj="$_connObj.WANPPPConnection"
cmclient -v ip_obj GETO "Device.IP.Interface.*.[LowerLayers,$ppp_obj]"
wanId=`help181_add_tr98obj "$wanppp_obj" "$ppp_obj" "$wan_index"`
[ -n "$wan_index" ] && wan_index=$(($wan_index+1))
if [ "$_user" = "EthernetLink" ]; then
cmclient -u "EthernetLink$_obj" SET "$_obj.$PARAM_TR098" "$_connObj.$_linkObj"
fi
cmclient -u "WANPPPConnection" SET "$wanppp_obj.$wanId.X_ADB_TR181_IPName" "$ip_obj"
cmclient -u "PPPIf$ppp_obj" SET "$ppp_obj.$PARAM_TR098" "$wanppp_obj.$wanId"
cmclient -u "IPIf$ip_obj" SET "$ip_obj.$PARAM_TR098" "$wanppp_obj.$wanId"
help98_add_wan_ipv4addr "$ip_obj" "$wanppp_obj.$wanId"
help98_add_portmap "$ip_obj" "$wanppp_obj.$wanId"
else
vlan_obj=`cmclient GETO "Device.Ethernet.VLANTermination.[LowerLayers=$_obj]"`
if [ -n "$vlan_obj" ]; then
if [ "$_user" = "EthernetLink" ]; then
cmclient -u "EthernetLink$_obj" SET "$_obj.$PARAM_TR098" "$_connObj.$_linkObj"
fi
cmclient -u "EthernetVLAN$vlan_obj" SET "$vlan_obj.$PARAM_TR098" "$_connObj.$_linkObj"
cmclient -v ip_obj GETO "Device.IP.Interface.*.[LowerLayers>$vlan_obj]"
if [ -n "$ip_obj" ]; then
wanip_obj="$_connObj.WANIPConnection"
wanId=`help181_add_tr98obj "$wanip_obj" "$ip_obj" "$wan_index"`
[ -n "$wan_index" ] && wan_index=$(($wan_index+1))
cmclient -u "IPIf$ip_obj" SET "$ip_obj.$PARAM_TR098" "$wanip_obj.$wanId"
help98_add_wan_ipv4addr "$ip_obj" "$wanip_obj.$wanId"
help98_add_dhcpclient "$ip_obj" "$wanip_obj.$wanId"
help98_add_portmap "$ip_obj" "$wanip_obj.$wanId"
else
cmclient -v ppp_obj GETO "Device.PPP.Interface.*.[LowerLayers>$vlan_obj]"
if [ -n "$ppp_obj" ]; then
wanppp_obj="$_connObj.WANPPPConnection"
ip_obj=`cmclient GETO "Device.IP.Interface.*.[LowerLayers=$ppp_obj]"`
wanId=`help181_add_tr98obj "$wanppp_obj" "$ppp_obj" "$wan_index"`
[ -n "$wan_index" ] && wan_index=$(($wan_index+1))
cmclient -u "WANPPPConnection" SET "$wanppp_obj.$wanId.X_ADB_TR181_IPName" "$ip_obj"
cmclient -u "PPPIf$ppp_obj" SET "$ppp_obj.$PARAM_TR098" "$wanppp_obj.$wanId"
cmclient -u "IPIf$ip_obj" SET "$ip_obj.$PARAM_TR098" "$wanppp_obj.$wanId"
help98_add_wan_ipv4addr "$ip_obj" "$wanppp_obj.$wanId"
help98_add_portmap "$ip_obj" "$wanppp_obj.$wanId"
fi
fi
fi
fi
fi
}
help98_build_wanconnection()
{
local id="$1" chan="$2" order="$3" ptmLink="" ptmEthLink=""
[ -z "$order" ] && order="atm ptm"
for o in $order; do
if [ "$o" = "atm" ]; then
for atm in `cmclient GETO "Device.ATM.Link.*.[LowerLayers=$chan]"`; do
conn_id=`help181_add_tr98obj "$OBJ_IGD.WANDevice.$id.WANConnectionDevice"`
dsllink_id=`help181_add_tr98obj "$OBJ_IGD.WANDevice.$id.WANConnectionDevice.$conn_id.WANDSLLinkConfig" "$atm"`
cmclient -u "ATMLink$atm" SET "$atm.$PARAM_TR098" "$OBJ_IGD.WANDevice.$id.WANConnectionDevice.$conn_id.WANDSLLinkConfig"
link_type=`cmclient GETV "$atm.LinkType"`
if [ "$link_type" = "EoA" ]; then
help98_add_bridge_availablelist "$OBJ_IGD.WANDevice.$id.WANConnectionDevice.$conn_id" "WANInterface"
for eth_link in `cmclient GETO "Device.Ethernet.Link.*.[LowerLayers=$atm]"`
do
help98_build_wan_ip_ppp "$eth_link" "$OBJ_IGD.WANDevice.$id.WANConnectionDevice.$conn_id" "EthernetLink" "WANDSLLinkConfig"
done
else
help98_build_wan_ip_ppp "$atm" "$OBJ_IGD.WANDevice.$id.WANConnectionDevice.$conn_id" "ATMLink" "WANDSLLinkConfig"
fi
done
fi
if [ "$o" = "ptm" ]; then
cmclient -v ptmLink GETO "Device.PTM.Link.*.[LowerLayers=$chan]"
for ptmLink in $ptmLink
do
cmclient -v ptmEthLink GETO "Device.Ethernet.Link.*.[LowerLayers=$ptmLink]"
for ptmEthLink in $ptmEthLink
do
conn_id=$(help181_add_tr98obj "$OBJ_IGD.WANDevice.$id.WANConnectionDevice")
help98_add_xan_xconfig "$OBJ_IGD.WANDevice.$id.WANConnectionDevice.$conn_id.WANPTMLinkConfig" "$ptmEthLink" "PTMLink$ptmEthLink"
cmclient SETE "$ptmLink.$PARAM_TR098" "$OBJ_IGD.WANDevice.$id.WANConnectionDevice.$conn_id.WANPTMLinkConfig"
help98_build_wan_ip_ppp "$ptmEthLink" "$OBJ_IGD.WANDevice.$id.WANConnectionDevice.$conn_id" "EthernetLink" "WANPTMLinkConfig"
done
done
fi
done
}
help98_destroy_wanconnection()
{
local id="$1"
$CM_CLIENT_TR098_TR181 DEL "$OBJ_IGD.WANDevice.$id.WANConnectionDevice." > /dev/null
}
Do_WANDeviceForAustria () {
for dsl in `cmclient GETO "Device.DSL.Line"`
do
id=`help181_add_tr98obj "$OBJ_IGD.WANDevice"`
dslintf_id=`help181_add_tr98obj "$OBJ_IGD.WANDevice.$id.WANDSLInterfaceConfig" "$dsl"`
cmclient -u "DslLine$dsl" SET "$dsl.$PARAM_TR098" "$OBJ_IGD.WANDevice.$id.WANDSLInterfaceConfig"
for chan in `cmclient GETO "Device.DSL.Channel.*.[LowerLayers=$dsl]"`
do
cmclient -u "DslChannel$chan" SET "$chan.$PARAM_TR098" "$OBJ_IGD.WANDevice.$id.WANDSLInterfaceConfig"
$CM_CLIENT_TR098_TR181 SET "$OBJ_IGD.WANDevice.$id.WANDSLInterfaceConfig.X_ADB_TR181_CHAN" "$chan" > /dev/null
lenc="`cmclient GETV $chan.LinkEncapsulationUsed`"
help98_destroy_wanconnection "$id"
case "$lenc" in
*ATM|"")
help98_build_wanconnection "$id" "$chan" "atm ptm"
;;
*PTM)
help98_build_wanconnection "$id" "$chan" "ptm atm"
;;
esac
done
done
for wan_eth in `cmclient GETO "Device.Ethernet.Interface.*.[Upstream=true]"`
do
wanDevId=`help181_add_tr98obj "$OBJ_IGD.WANDevice"`
wanEthIf_inst=`help181_add_tr98obj "$OBJ_IGD.WANDevice.$wanDevId.WANEthernetInterfaceConfig" "$wan_eth"`
cmclient -u "EthernetIf$wan_eth" SET "$wan_eth.$PARAM_TR098" "$OBJ_IGD.WANDevice.$wanDevId.WANEthernetInterfaceConfig"
for eth_link in `cmclient GETO "Device.Ethernet.Link.*.[LowerLayers=$wan_eth]"`
do
conn_id=`help181_add_tr98obj "$OBJ_IGD.WANDevice.$wanDevId.WANConnectionDevice"`
help98_add_xan_xconfig "$OBJ_IGD.WANDevice.$wanDevId.WANConnectionDevice.$conn_id.WANEthernetLinkConfig" "$eth_link" "EthernetLink$eth_link"
help98_build_wan_ip_ppp "$eth_link" "$OBJ_IGD.WANDevice.$wanDevId.WANConnectionDevice.$conn_id" "EthernetLink" "WANEthernetLinkConfig"
done
done
}
[ "`basename $0`" != "TR098_AlignAll.sh" ] &&  return
. /etc/ah/helper_serialize.sh && help_serialize "TR098_AlignAll_running" > /dev/null
for bridge in `cmclient GETO "Device.Bridging.Bridge"`
do
bridgeId=`help181_add_tr98obj "$OBJ_IGD.Layer2Bridging.Bridge" "$bridge"`
cmclient SET "$bridge.$PARAM_TR098" "$OBJ_IGD.Layer2Bridging.Bridge.$bridgeId"
managPort=`cmclient GETO "$bridge.Port.[ManagementPort=true]"`
if [ -n "$managPort" ]; then
cmclient SET "$managPort.$PARAM_TR098" "$OBJ_IGD.Layer2Bridging.Bridge.$bridgeId"
ipif=`ip_interface_get "$managPort"`
if [ -n "$ipif" ]; then
lan_id=`help181_add_tr98obj "$OBJ_IGD.LANDevice" "" "$lan_index"`
[ -n "$lan_index" ] && let "lan_index += 1"
help98_build_lan_ipinterface "$ipif" "$lan_id"
fi
else
continue;
fi
for port in `cmclient GETO "$bridge.Port.*.[ManagementPort=false]"`
do
portId=`help181_add_tr98obj "$OBJ_IGD.Layer2Bridging.Bridge.$bridgeId.Port" "$port"`
cmclient SET "$port.$PARAM_TR098" "$OBJ_IGD.Layer2Bridging.Bridge.$bridgeId.Port.$portId"
llayer=`cmclient GETV "$port.LowerLayers"`
case $llayer in
*"Ethernet.Interface"*)
is_up=`cmclient GETV "$llayer.Upstream"`
if [ "$is_up" = "false" ]; then
bridged_lan_list="$bridged_lan_list""$llayer"
help98_add_xan_xconfig "$OBJ_IGD.LANDevice.$lan_id.LANEthernetInterfaceConfig" "$llayer" "EthernetIf$llayer"
else
llayer98=`cmclient GETV "$llayer.$PARAM_TR098"`
help98_add_bridge_availablelist "$llayer98" "WANInterface"
fi
;;
*"WiFi"*)
bridged_wlan_list="$bridged_wlan_list""$llayer"
help98_add_xan_xconfig "$OBJ_IGD.LANDevice.$lan_id.WLANConfiguration" "$llayer" "WiFiSSID$llayer"
;;
*)
;;
esac
done
cmclient -v bridge_type GETV "$bridge.Standard"
if [ "$bridge_type" = "802.1Q-2005" ]; then
_setm=""
cmclient -v VLANobj GETO "$bridge.VLAN"
for VLANobj in $VLANobj
do
VLANtr181Idx=${VLANobj##*VLAN.}
VLANtr098Idx=`help181_add_tr98obj "$OBJ_IGD.Layer2Bridging.Bridge.$bridgeId.VLAN" "$VLANobj"`
_vlanTR098="$OBJ_IGD.Layer2Bridging.Bridge.$bridgeId.VLAN.$VLANtr098Idx"
cmclient SET "$bridge.VLAN.$VLANtr181Idx.$PARAM_TR098" "$_vlanTR098"
done
fi
done
for lan_eth in `cmclient GETO "Device.Ethernet.Interface.*.[Upstream=false]"`
do
case "$bridged_lan_list" in
*"$lan_eth"*)
continue;
;;
esac
eth_link=`cmclient GETO "Device.Ethernet.Link.*.[LowerLayers=$lan_eth]"`
if [ -n "$eth_link" ]; then
ipif=`ip_interface_get "$lan_eth"`
if [ -n "$ipif" ]; then
lan_id=`help181_add_tr98obj "$OBJ_IGD.LANDevice" "" "$lan_index"`
[ -n "$lan_index" ] && let "lan_index += 1"
help98_build_lan_ipinterface "$ipif" "$lan_id"
help98_add_xan_xconfig "$OBJ_IGD.LANDevice.$lan_id.LANEthernetInterfaceConfig" "$lan_eth" "EthernetIf$lan_eth"
fi
else
help98_add_lan_default "$lan_eth" "LANEthernetInterfaceConfig" "EthernetIf"
fi
done
for wlan in `cmclient GETO "Device.WiFi.SSID"`
do
case "$bridged_wlan_list" in
*"$wlan"*)
continue;
;;
esac
eth_link=`cmclient GETO "Device.Ethernet.Link.*.[LowerLayers=$wlan]"`
if [ -n "$eth_link" ]; then
ipif=`ip_interface_get "$wlan"`
if [ -n "$ipif" ]; then
lan_id=`help181_add_tr98obj "$OBJ_IGD.LANDevice" "" "$lan_index"`
[ -n "$lan_index" ] && let "lan_index += 1"
help98_build_lan_ipinterface "$ipif" "$lan_id"
help98_add_xan_xconfig "$OBJ_IGD.LANDevice.$lan_id.WLANConfiguration" "$wlan" "WiFiSSID$wlan"
fi
else
help98_add_lan_default "$wlan" "WLANConfiguration" "WiFiSSID"
fi
done
for wan_eth in `cmclient GETO "Device.Ethernet.Interface.*.[Upstream=true]"`
do
wanDevId=`help181_add_tr98obj "$OBJ_IGD.WANDevice"`
wanEthIf_inst=`help181_add_tr98obj "$OBJ_IGD.WANDevice.$wanDevId.WANEthernetInterfaceConfig" "$wan_eth"`
cmclient -u "EthernetIf$wan_eth" SET "$wan_eth.$PARAM_TR098" "$OBJ_IGD.WANDevice.$wanDevId.WANEthernetInterfaceConfig"
for eth_link in `cmclient GETO "Device.Ethernet.Link.*.[LowerLayers=$wan_eth]"`
do
conn_id=`help181_add_tr98obj "$OBJ_IGD.WANDevice.$wanDevId.WANConnectionDevice"`
help98_add_xan_xconfig "$OBJ_IGD.WANDevice.$wanDevId.WANConnectionDevice.$conn_id.WANEthernetLinkConfig" "$eth_link" "EthernetLink$eth_link"
help98_build_wan_ip_ppp "$eth_link" "$OBJ_IGD.WANDevice.$wanDevId.WANConnectionDevice.$conn_id" "EthernetLink" "WANEthernetLinkConfig"
done
done
for dsl in `cmclient GETO "Device.DSL.Line"`
do
id=`help181_add_tr98obj "$OBJ_IGD.WANDevice"`
dslintf_id=`help181_add_tr98obj "$OBJ_IGD.WANDevice.$id.WANDSLInterfaceConfig" "$dsl"`
cmclient -u "DslLine$dsl" SET "$dsl.$PARAM_TR098" "$OBJ_IGD.WANDevice.$id.WANDSLInterfaceConfig"
for chan in `cmclient GETO "Device.DSL.Channel.*.[LowerLayers=$dsl]"`
do
cmclient -u "DslChannel$chan" SET "$chan.$PARAM_TR098" "$OBJ_IGD.WANDevice.$id.WANDSLInterfaceConfig"
$CM_CLIENT_TR098_TR181 SET "$OBJ_IGD.WANDevice.$id.WANDSLInterfaceConfig.X_ADB_TR181_CHAN" "$chan" > /dev/null
help98_build_wanconnection "$id" "$chan" "atm ptm"
done
done
for wan_usb in `cmclient GETO "Device.USB.Interface.*.[Upstream=true]"`
do
wanDevId=`help181_add_tr98obj "$OBJ_IGD.WANDevice"`
help181_add_tr98obj "$OBJ_IGD.WANDevice.$wanDevId.X_ADB_WANUSBInterfaceConfig" "$wan_usb"
cmclient SET "$wan_usb.$PARAM_TR098" "$OBJ_IGD.WANDevice.$wanDevId.X_ADB_WANUSBInterfaceConfig"
for modemObj in `cmclient GETO "Device.X_ADB_MobileModem.Interface.[LowerLayers=$wan_usb]"`
do
cmclient -v pppObj GETO "Device.PPP.Interface.[LowerLayers=$modemObj]"
if [ -n "$pppObj" ]; then
conn_id=`help181_add_tr98obj "$OBJ_IGD.WANDevice.$wanDevId.WANConnectionDevice"`
wanppp_obj="$OBJ_IGD.WANDevice.$wanDevId.WANConnectionDevice.$conn_id.WANPPPConnection"
pppId=`help181_add_tr98obj "$wanppp_obj" "$pppObj" "$wan_index"`
cmclient -u "PPPIf$pppObj" SET "$pppObj.$PARAM_TR098" "$wanppp_obj.$pppId"
cmclient -v ipObj GETO "Device.IP.Interface.*.[LowerLayers=$pppObj]"
if [ -n "$ipObj" ]; then
cmclient -u "WANPPPConnection" SET "$wanppp_obj.$pppId.X_ADB_TR181_IPName" "$ipObj"
cmclient -u "IPIf$ipObj" SET "$ipObj.$PARAM_TR098" "$wanppp_obj.$pppId"
help98_add_wan_ipv4addr "$ipObj" "$wanppp_obj.$pppId"
help98_add_portmap "$ipObj" "$wanppp_obj.$pppId"
fi
fi
done
done
for route in `cmclient GETO "Device.Routing.Router.*.IPv4Forwarding"`
do
l3forw_id=`help181_add_tr98obj "$OBJ_IGD.Layer3Forwarding.Forwarding" "$route"`
cmclient -u "boot" SET "$route.$PARAM_TR098" "$OBJ_IGD.Layer3Forwarding.Forwarding.$l3forw_id"
done
for host in `cmclient GETO "Device.Hosts.Host"`
do
l1intf=`cmclient GETV "$host.Layer1Interface"`
if [ -n "$l1intf" ]; then
l1_tr098=`cmclient GETV "$l1intf.$PARAM_TR098"`
if [ -n "$l1_tr098" ]; then
lan_tmp="${l1_tr098#*LANDevice.[0-9]*.}"
lan_device="${l1_tr098%.$lan_tmp*}"
case "$lan_device" in
*"LANDevice"*)
hostId=`help181_add_tr98obj "$lan_device.Hosts.Host" "$host"`
cmclient SET "$host.$PARAM_TR098" "$lan_device.Hosts.Host.$hostId"
;;
esac
fi
fi
done
cmclient SET "Device.QoS.$PARAM_TR098" "$OBJ_IGD.QueueManagement"
for qos_obj in App Classification Flow Policer Queue QueueStats
do
for qos in `cmclient GETO "Device.QoS.$qos_obj"`
do
qosId=`help181_add_tr98obj "$OBJ_IGD.QueueManagement.$qos_obj" "$qos"`
cmclient -u "QoS$qos_obj$qos" SET "$qos.$PARAM_TR098" "$OBJ_IGD.QueueManagement.$qos_obj.$qosId"
done
done
cmclient SET "Device.Time.$PARAM_TR098" "$OBJ_IGD.Time"
exit 0
