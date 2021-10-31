#!/bin/sh
FW_CHAIN_PREFIX="TunnelCli"
FW_CHAIN_FILTERFWD="ForwardAllow_Tunnel"
FW_CHAIN_FILTERIN="TunnelIn"
command -v help_iptables >/dev/null || . /etc/ah/helper_firewall.sh
command -v help_check_ip_in_network >/dev/null || . /etc/ah/helper_ipcalc.sh
tunnel_update_firewall() {
local cmd="$1" user="$2" address="$3" _chain \
user_obj lan_ip access_right
[ -z "$cmd" -o -z "$user" -o -z "$address" ] && return
_chain="${FW_CHAIN_PREFIX}_${user}_${address##*.}"
case "$cmd" in
"add")
help_iptables -N "$_chain"
help_iptables -I "$FW_CHAIN_FILTERFWD" -j "$_chain"
help_iptables -I "$FW_CHAIN_FILTERIN" -j "$_chain"
;;
"del")
help_iptables -D "$FW_CHAIN_FILTERFWD" -j "$_chain"
help_iptables -D "$FW_CHAIN_FILTERIN" -j "$_chain"
help_iptables -F "$_chain"
help_iptables -X "$_chain"
return
;;
esac
help_iptables -A "$_chain" -s "$address" -j ACCEPT
}
check_host_route_link() {
local hostname="$1" interface="$2" obj addrs addr_ip addr_mask tmp
cmclient -v addrs GETO "$interface.IPv4Address.[Enable=true]"
for obj in $addrs; do
cmclient -v addr_ip GETV "$obj.IPAddress"
cmclient -v addr_mask GETV "$obj.SubnetMask"
help_check_ip_in_network "$hostname" "$addr_ip" "$addr_mask" && return 0
done
return 1
}
check_host_route() {
local hostname="$1" interface="$2" obj routes route_ip route_mask route_type
cmclient -v routes GETO "Device.Routing.Router.IPv4Forwarding.[Interface=$interface].[Enable=true]"
for obj in $routes; do
cmclient -v route_ip GETV "$obj.DestIPAddress"
cmclient -v route_mask GETV "$obj.DestSubnetMask"
cmclient -v route_type GETV "$obj.StaticRoute"
[ -z "$route_ip" ] && continue
[ -z "$route_mask" ] && route_mask="255.255.255.255"
if help_check_ip_in_network "$hostname" "$route_ip" "$route_mask"; then
[ "$route_type" != "false" ] && return 0
cmclient DEL "$obj"
fi
done
return 1
}
add_tunnel_route() {
local path="$1" tunnel_ipif hostname def_route_addr new_route
cmclient -v tunnel_ipif GETV "${path}.Interface"
cmclient -v def_route_addr GETV Device.Routing.Router.IPv4Forwarding.[Interface=$tunnel_ipif].[DestIPAddress=""].GatewayIPAddress
cmclient -v hostname GETV "${path}.Hostname"
[ -n "$tunnel_ipif" -a -n "$hostname" ] || return 1
hostname=$(host ${hostname})
for hostname in $hostname; do
case "$hostname" in
*":"*)
continue ;;
esac
check_host_route_link "$hostname" "$tunnel_ipif" && continue
[ -n "$def_route_addr" ] || return 1
check_host_route "$hostname" "$tunnel_ipif" && continue
cmclient -v new_route ADD "Device.Routing.Router.IPv4Forwarding.[Interface=${tunnel_ipif}].[StaticRoute=false].[DestIPAddress=$hostname].[GatewayIPAddress=$def_route_addr]"
cmclient SET "Device.Routing.Router.IPv4Forwarding.${new_route}.Enable" true
done
return 0
}
