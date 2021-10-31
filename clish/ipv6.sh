#!/bin/sh
. /etc/clish/clish-commons.sh
print_param() {
	local val
	cmclient -v val GETV "Device.IP.${2}"
	print_2_col_row "$1" "$val" "30"
}
show() {
	local var
	printf "\n"
	printf "IPv6 configuration:\n"
	print_horizontal_line "80"
	print_param "Enable" "IPv6Enable"
	print_param "Status" "IPv6Status"
	print_param "ULA Prefix" "ULAPrefix"
	print_param "Encapsulation IPv6 to IPv4" "X_ADB_6to4Enable"
	cmclient -v var GETV "Device.IP.X_ADB_6to4AddressSource"
	[ -n "$var" ] && cmclient -v var GETV "$var"
	print_2_col_row "IPv6 to IPv4 address source" "$var" "30"
	print_horizontal_line "80"
	printf "\n"
}
show_addr() {
	local this="$1"
	local i prefix
	echo
	echo "Current configuration"
	print_horizontal_line
	for i in \
		Enable Status IPAddressStatus IPAddress \
		Anycast Origin PreferredLifetime ValidLifetime; do
		show_from_cm "$this" "$i"
	done
	cmclient -v prefix GETV "$this.Prefix"
	cmclient -v prefix GETV "$prefix.Prefix"
	print_2_col_row "Prefix" "$prefix"
	print_horizontal_line
}
show_prefix() {
	local this="$1"
	local i
	echo
	echo "Current configuration"
	print_horizontal_line
	for i in \
		Enable Status PrefixStatus \
		Prefix Origin StaticType \
		OnLink Autonomous \
		PreferredLifetime ValidLifetime; do
		show_from_cm "$this" "$i"
	done
	print_horizontal_line
}
case "$1" in
"show")
	show
	;;
"show_addr")
	show_addr "$2"
	;;
"show_prefix")
	show_prefix "$2"
	;;
"set_time")
	case "$4" in
	inf)
		exec /etc/clish/quick_cm.sh "set" "$2" "$3" "9999-12-31T23:59:59Z"
		;;
	*)
		exec /etc/clish/quick_cm.sh "set" "$2" "$3" "$4"
		;;
	esac
	;;
*)
	exec /etc/clish/quick_cm.sh "$1" "$2" "$3" "$4"
	;;
esac
