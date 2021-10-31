#!/bin/sh
. /etc/clish/clish-commons.sh
get_neigh_disc_setting_from_iface() {
	local cli_iface="$1"
	local neigh_disc_setting_obj
	cmclient -v neigh_disc_setting_obj GETO \
		"Device.NeighborDiscovery.InterfaceSetting.[Interface=$(ll_obj_to_ip_obj $(cli_to_tr $cli_iface))]"
	echo "$neigh_disc_setting_obj"
}
show_configuration() {
	local param="$1"
	local show_setting_obj each_obj dm_param dm_value
	if [ "$param" = "all" ]; then
		cmclient -v show_setting_obj GETO "Device.NeighborDiscovery.InterfaceSetting"
		printf "\n"
		printf "Neighbor Discovery:\n"
		print_horizontal_line
		cmclient -v dm_value GETV "Device.NeighborDiscovery.Enable"
		print_2_col_row "Enable" "$dm_value"
		cmclient -v dm_value GETV "Device.NeighborDiscovery.InterfaceSettingNumberOfEntries"
		print_2_col_row "InterfaceSettings" "$dm_value"
	else
		show_setting_obj="$(get_neigh_disc_setting_from_iface $param)"
	fi
	print_horizontal_line
	for each_obj in $show_setting_obj; do
		cmclient -v dm_value GETV "$each_obj.Interface"
		print_2_col_row "Setting for interface" "$(tr_to_cli $(ip_interface_get_cli_ll $dm_value))"
		for dm_param in "Enable" "Status" "Alias" \
			"RtrSolicitationInterval" "MaxRtrSolicitations" "RSEnable"; do
			show_from_cm "$each_obj" "$dm_param"
		done
		print_horizontal_line
	done
}
allow_interface_setting_enable() {
	local ip_obj="$(ll_obj_to_ip_obj $(cli_to_tr $1))"
	local ipv6_enable
	cmclient -v ipv6_enable GETV "$ip_obj.IPv6Enable"
	[ "$ipv6_enable" = "true" ] && return 0 || return 1
}
command="$1"
setm=""
case "$command" in
"enable_on_iface")
	allow_interface_setting_enable $2 &&
		setm="$(get_neigh_disc_setting_from_iface $2).Enable=true" ||
		die "ERROR: Enable IPv6 support for $2 at first."
	;;
"show")
	show_configuration "$2"
	;;
"simple_set")
	setm="$(get_neigh_disc_setting_from_iface $2).$3=$4"
	;;
*)
	die "ERROR: Unknown command"
	;;
esac
[ -n "$setm" ] && exec /etc/clish/quick_cm.sh "setm" "$setm"
