#!/bin/sh
. /etc/clish/clish-commons.sh
show_client() {
	local i var
	show_from_cm "$OBJ" "Alias"
	print_horizontal_line "80"
	for i in Enable Status Hostname; do
		show_from_cm "$OBJ" "$i"
	done
	show_from_cm_interface "$OBJ.Interface"
	show_from_cm "$OBJ" "LastError"
	cmclient -v var GETV "%($OBJ.Provider).Name"
	print_2_col_row "Provider" "$var"
	for i in Username Password Offline IPv6Support; do
		show_from_cm "$OBJ" "$i"
	done
	print_horizontal_line "80"
	printf "\n"
}
show_provider() {
	show_from_cm "$OBJ" "Name"
	print_horizontal_line "80"
	for i in Protocol BaseURI; do
		show_from_cm "$OBJ" "$i"
	done
	print_horizontal_line "80"
	printf "\n"
}
show_all_providers() {
	local obj obj_list
	cmclient -v obj_list GETO "Device.Services.X_ADB_DynamicDNS.Provider"
	[ ${#obj_list} -eq 0 ] && printf "Providers table is empty!\n\n" && return
	for OBJ in $obj_list; do
		show_provider
	done
}
show_all_clients() {
	local obj_list iface objAccess any
	any=0
	cmclient -v obj_list GETO "Device.Services.X_ADB_DynamicDNS.Client"
	for OBJ in $obj_list; do
		objAccess=1
		cmclient -v iface GETV "$OBJ.Interface"
		[ -n "$iface" ] && get_obj_access objAccess "$iface"
		if [ $objAccess -gt 0 ]; then
			show_client
			any=1
		fi
	done
	[ $any -eq 0 ] && printf "Client table is empty!\n\n"
}
OBJ="$2"
case "$1" in
show_*)
	printf "\n"
	eval "$1"
	;;
*) exec /etc/clish/quick_cm.sh "$1" "$2" "$3" "$4" ;;
esac
