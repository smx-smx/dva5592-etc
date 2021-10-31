#!/bin/sh
. /etc/clish/clish-commons.sh
. /etc/ah/helper_ipcalc.sh
console_output() {
printf "$printf_args" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}
route_print_one_entry() {
local ipver="$1"
local obj="$2"
local throw_away_disabled="$3"
local Interface ForwardingMetric DestIPAddress GatewayIPAddress DestSubnetMask NextHop \
ExpirationTime DestIPPrefix enabled Status cli_iface tmp_enable
cmclient -v Interface GETV $obj.Interface
cmclient -v ForwardingMetric GETV $obj.ForwardingMetric
[ "$ForwardingMetric" = "-1" ] && ForwardingMetric=""
cmclient -v enabled GETV $obj.Enable
[ "false" = "$enabled" -a "1" = "$throw_away_disabled" ] && return
[ "0" = "$throw_away_disabled" ] && tmp_enable="$enabled"
cmclient -v Status GETV $obj.Status
cmclient -v InterfaceAlias GETV $Interface.Alias
cli_iface=$(tr_to_cli $(ip_interface_get_cli_ll "$Interface"))
if [ "v4" = "$ipver" ]; then
cmclient -v DestIPAddress GETV $obj.DestIPAddress
cmclient -v GatewayIPAddress GETV $obj.GatewayIPAddress
cmclient -v DestSubnetMask GETV $obj.DestSubnetMask
if [ '' = "$DestIPAddress" ]; then
DestIPAddress="0.0.0.0"
fi
if [ '' = "$DestSubnetMask" ]; then
DestSubnetMask="0.0.0.0"
fi
console_output  "`tr_to_cli $obj`" \
"$DestIPAddress" \
"$DestSubnetMask" \
"$GatewayIPAddress" \
"$ForwardingMetric" \
"$cli_iface" \
"$InterfaceAlias" \
"$Status" \
"$tmp_enable"
else
cmclient -v NextHop GETV $obj.NextHop
cmclient -v DestIPPrefix GETV $obj.DestIPPrefix
cmclient -v ExpirationTime GETV $obj.ExpirationTime
case "$ExpirationTime" in
"9999-12-31T23:59:59Z")
ExpirationTime="Infinite"
;;
"0001-01-01T00:00:00Z")
ExpirationTime="Indefinite"
;;
*)
ExpirationTime=$(help_str_replace "T" " " "$ExpirationTime")
ExpirationTime=${ExpirationTime%Z}
;;
esac
printf "$printf_args" \
"`tr_to_cli $obj`" \
"$DestIPPrefix" \
"$NextHop" \
"$ExpirationTime" \
"$ForwardingMetric" \
"$cli_iface" \
"$InterfaceAlias" \
"$Status" \
"$tmp_enable"
fi
}
route_print_onlink_routes() {
local ipver="$1"
local throw_away_disabled="$2"
local entries name addr mask gw metric exp_time cli_iface sfx i enabled status tmp_enable
if [ "v4" = "$ipver" ]; then
sfx="Address"
else
sfx="Prefix"
fi
cmclient -v entries GETO Device.IP.Interface.IP${ipver}${sfx}
name="---"
for i in $entries; do
cli_iface=$(tr_to_cli $(ip_interface_get_cli_ll ${i%.IP${ipver}${sfx}*}))
cmclient -v InterfaceAlias GETV ${i%.IP${ipver}${sfx}*}.Alias
cmclient -v enabled GETV $i.Enable
[ "false" = "$enabled" -a "1" = "$throw_away_disabled" ] && continue
[ "0" = "$throw_away_disabled" ] && tmp_enable="$enabled"
cmclient -v status GETV $i.Status
if [ "v4" = "$ipver" ]; then
cmclient -v addr GETV $i.IPAddress
[ -z "$addr" ] && continue
cmclient -v mask GETV $i.SubnetMask
[ -z "$mask" ] && mask="255.255.255.255"
gw="0.0.0.0"
metric=""
help_calc_network addr $addr $mask
console_output "$name" \
"$addr" \
"$mask" \
"$gw" \
"$metric" \
"$cli_iface" \
"${InterfaceAlias}" \
"$status" \
"$tmp_enable"
else
cmclient -v addr GETV $i.Prefix
cmclient -v exp_time GETV $i.ValidLifetime
case "$addr" in
"fe80:"*) continue ;;
esac
gw=""
metric=""
console_output "$name" \
"$addr" \
"$gw" \
"$exp_time" \
"$metric" \
"$cli_iface" \
"${InterfaceAlias}" \
"$status" \
"$tmp_enable"
fi
done
if [ "v4" = "$ipver" ]; then
cmclient -v entries GETO Device.NAT.InterfaceSetting
for i in $entries; do
local ip_addrs if_enabled
cmclient -v addr GETV $i.X_ADB_ExternalIPAddress
[ -z "$addr" ] && continue
cmclient -v cli_iface GETV $i.Interface
[ -z "$cli_iface" ] && continue
cmclient -v ip_addrs GETO $cli_iface.IPv4Address.[IPAddress=$addr]
[ -n "$ip_addrs" ] && continue
cmclient -v enabled GETV $cli_iface.Enable
cmclient -V InterfaceAlias GETV $cli_iface.Alias
cli_iface=$(tr_to_cli $cli_iface)
cmclient -v mask GETV $i.X_ADB_ExternalIPMask
cmclient -v enabled GETV $i.Enable
cmclient -v status GETV $i.Status
[ -z "$mask" ] && mask="255.255.255.255"
gw="0.0.0.0"
metric=""
help_calc_network addr $addr $mask
[ "$enabled" = "true" ] && enabled="$if_enabled"
[ "false" = "$enabled" -a "1" = "$throw_away_disabled" ] && continue
[ "0" = "$throw_away_disabled" ] && tmp_enable="$enabled"
console_output "$name" \
"$addr" \
"$mask" \
"$gw" \
"$metric" \
"$cli_iface" \
"$InterfaceAlias" \
"$status" \
"$tmp_enable"
done
fi
}
route_show() {
local ipver="$1"
local route_obj="$2"
if [ "all" != "$route_obj" ]; then
local throw_away_disabled="0"
local enable_label="Enable"
local enable_pattern=" %-6s"
else
local throw_away_disabled="1"
local enable_pattern="%s"
fi
local objs
if [ "v4" = "$ipver" ]; then
printf_args="%-10s %-15s %-15s %-15s %-6s %-10s %-10.10s %-10s${enable_pattern}\n"
printf "$printf_args" "Name" "Destination" "Netmask" "Gateway" "Metric" \
"Interface" "Alias" "Status" "$enable_label"
else
printf_args="%-10s %-40s %-40s %-20s %-6s %-10s %-10.10s %-10s${enable_pattern}\n"
printf "$printf_args" "Name" "Prefix" "Next Hop" "Expiration Time" "Metric" \
"Interface" "Alias" "Status" "$enable_label"
fi
if [ "all" = "$route_obj" ]; then
route_print_onlink_routes "$ipver" "$throw_away_disabled"
cmclient -v objs GETO Device.Routing.Router.1.IP${ipver}Forwarding
else
objs="$route_obj"
fi
for obj in $objs; do
route_print_one_entry "$ipver" "$obj" "$printf_args" "$throw_away_disabled"
done
}
route_generic_show() {
local obj="$1"
if [ "all" = "$obj" ]; then
echo "IPv4 Routing table:"
route_show v4 all
[ "false" = "`cmclient GETV Device.IP.IPv6Enable`" ] && return 0
echo ""
echo "IPv6 Routing table:"
route_show v6 all
elif [ -z "${obj%%*IPv6Forwarding*}" ]; then
[ "false" = "`cmclient GETV Device.IP.IPv6Enable`" ] && return 0
route_show v6 "$obj"
else
route_show v4 "$obj"
fi
}
