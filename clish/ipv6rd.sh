#!/bin/sh
. /etc/clish/clish-commons.sh
obj=""
cell_width="30"
line_lenght="80"
print_param() {
	local val
	cmclient -v val GETV "$obj.$2"
	print_2_col_row "$1" "$val" "$cell_width"
}
print_list() {
	local message="$1"
	local list val
	cmclient -v list GETV "$obj.$2"
	list="$(list_print $list)"
	for val in $list; do
		print_2_col_row "$message" "$val" "$cell_width"
		message=""
	done
	[ -z "$list" ] && print_2_col_row "$message" "" "$cell_width"
}
print_interface() {
	local iface
	cmclient -v iface GETV "$obj.$2"
	iface="$(ip_interface_get_cli_ll $iface)"
	iface="$(tr_to_cli $iface)"
	print_2_col_row "$1" "$iface" "$cell_width"
}
print_address() {
	local addr
	cmclient -v addr GETV "$obj.$2"
	cmclient -v addr GETV "$addr.IPAddress"
	print_2_col_row "$1" "$addr" "$cell_width"
}
show_ipv6rd() {
	printf "\n"
	printf "IPv6 Rapid Deployment status:\n"
	print_horizontal_line "$line_lenght"
	obj="Device.IPv6rd"
	print_param "Enable" "Enable"
	print_horizontal_line "$line_lenght"
	printf "\n"
}
show_setting() {
	printf "\n"
	print_2_col_row "IPv6 RD setting name" "$(tr_to_cli $obj)" "$cell_width"
	print_horizontal_line "$line_lenght"
	print_param "Enable" "Enable"
	print_param "Status" "Status"
	print_list "Border Relay IPv4 addresses" "BorderRelayIPv4Addresses"
	print_param "All traffic to border relay" "AllTrafficToBorderRelay"
	print_param "Service provider's IPv6 prefix" "SPIPv6Prefix"
	print_param "IPv4 mask length" "IPv4MaskLength"
	print_address "Address source" "AddressSource"
	print_interface "Tunnel interface" "TunnelInterface"
	print_interface "Tunneled interface" "TunneledInterface"
	print_horizontal_line "$line_lenght"
	printf "\n"
}
show_statistic() {
	printf "Statistics:\n"
	print_horizontal_line "$line_lenght"
	print_param "Bytes sent" "BytesSent"
	print_param "Bytes received" "BytesReceived"
	print_param "Packets sent" "PacketsSent"
	print_param "Packets received" "PacketsReceived"
	print_param "Errors received" "ErrorsReceived"
	print_param "Discard packets received" "DiscardPacketsReceived"
	print_horizontal_line "$line_lenght"
	printf "\n"
}
show() {
	local obj_list
	if [ "$1" != "all" ]; then
		obj_list="$(cli_to_tr $1)"
	else
		cmclient -v obj_list GETO "Device.IPv6rd.InterfaceSetting"
	fi
	[ "$1" = "all" ] && show_ipv6rd
	[ -z "$obj_list" ] && printf "\nIPv6 Rapid Deployment not configured\n\n"
	for obj in $obj_list; do
		show_setting
		obj="$obj.X_ADB_Stats"
		show_statistic
	done
}
case "$1" in
"add_tunnel")
	cmclient -v res ADD "$2"
	cm_err_maybe_die "$res" "ERROR: failed to execute command"
	name="$(tr_to_cli $2.$res)"
	[ -n "$name" ] && echo "INFO: $name created"
	exec /etc/clish/quick_cm.sh setm "$2.$res.TunneledInterface=$3	$2.$res.TunnelInterface=$4	$3.Type=Tunneled	$4.Type=Tunnel"
	;;
"add_addr" | "del_addr")
	setm="$(handle_list_actions $(cli_to_tr $2).$3 ${1%_addr} $4)"
	[ -n "$setm" ] && exec /etc/clish/quick_cm.sh setm "$setm"
	;;
"show")
	show "$2"
	;;
"del")
	obj=$(cli_to_tr $2)
	cmclient -v wan GETV "$obj.TunneledInterface"
	cmclient -v lan GETV "$obj.TunnelInterface"
	for ifname in $wan $lan; do
		cmclient -v res SET "$ifname.Type" "Normal"
		cm_err_maybe_die "$res" "ERROR: failed to execute command"
	done
	exec /etc/clish/quick_cm.sh "del" "$2"
	;;
*)
	exec /etc/clish/quick_cm.sh "$1" "$2" "$3" "$4"
	;;
esac
