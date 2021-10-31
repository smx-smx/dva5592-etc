#/bin/sh
. /etc/clish/clish-commons.sh
OBJ=""
show() {
	local obj interface desc ePort iClient iPort proto ePortEnd additional row
	local portMappingEnable portMappingStatus
	local row1=45
	local row2=20
	local row3=15
	local row4=15
	local row5=15
	local row6=10
	local row7=10
	local prefix="$1"
	local table_format="|%-${row1}s|%-${row2}s|%-${row3}s|%-${row4}s|%-${row5}s|%-${row6}s|%-${row7}s|\n"
	printf "$table_format" "$(dup_char $row1)" "$(dup_char $row2)" "$(dup_char $row3)" "$(dup_char $row4)" "$(dup_char $row5)" "$(dup_char $row6)" "$(dup_char $row7)"
	printf "$table_format" "      PortMapping Name" "Coming from" " External Port" "  Local Host" " Internal Port" " Enable" " Status"
	printf "$table_format" "$(dup_char $row1)" "$(dup_char $row2)" "$(dup_char $row3)" "$(dup_char $row4)" "$(dup_char $row5)" "$(dup_char $row6)" "$(dup_char $row7)"
	for obj in $(cmclient GETO Device.NAT.PortMapping); do
		cmclient -v interface GETV $obj.AllInterfaces
		if [ "$interface" = "false" ]; then
			local ext_address
			cmclient -v interface GETV $obj.Interface
			cmclient -v ext_address GETV $obj.${prefix}ExternalIPAddress
			interface=$(tr_to_cli $(ip_interface_get_cli_ll $interface))
			if [ -n "$ext_address" ]; then
				cmclient -v ext_address GETV "$ext_address.${prefix}ExternalIPAddress"
				interface="$interface-$ext_address"
			else
				interface="$interface-default"
			fi
		else
			interface="all"
		fi
		name=$(tr_to_cli $obj)
		cmclient -v desc GETV $obj.Description
		cmclient -v ePort GETV $obj.ExternalPort
		cmclient -v iClient GETV $obj.InternalClient
		cmclient -v iPort GETV $obj.InternalPort
		cmclient -v proto GETV $obj.Protocol
		cmclient -v ePortEnd GETV $obj.ExternalPortEndRange
		cmclient -v additional GETV $obj.${prefix}AdditionalExternalPort
		cmclient -v portMappingEnable GETV $obj.Enable
		cmclient -v portMappingStatus GETV $obj.Status
		[ "$iPort" = "0" ] && iPort="Same Port"
		if [ "$proto" = "X_ADB_GRE" ]; then
			proto="GRE"
		else
			proto="$proto:$ePort"
		fi
		[ "$ePortEnd" != "0" ] && proto="$proto-$ePortEnd"
		printf "$table_format" "$name" "$interface" "$proto" "$iClient" "$iPort" "$portMappingEnable" "$portMappingStatus"
		row=1
		IFS=","
		for proto in $(cmclient GETV $obj.${prefix}AdditionalExternalPort); do
			if [ $row -eq 1 ]; then
				printf "$table_format" "$desc" "" "$proto" "" ""
			else
				printf "$table_format" "" "" "$proto" "" ""
			fi
			row=$(($row + 1))
		done
		unset IFS
		[ $row -eq 1 -a -n "$desc" ] && printf "$table_format" "$desc" "" "" "" ""
		printf "$table_format" "$(dup_char $row1)" "$(dup_char $row2)" "$(dup_char $row3)" "$(dup_char $row4)" "$(dup_char $row5)" "$(dup_char $row6)" "$(dup_char $row7)"
	done
}
in_traffic_add_external_port() {
	local pmap_obj="$1"
	local port="$2"
	local prefix="$3"
	local proto start_port end_port
	cmclient -v ex_port GETV "${pmap_obj}.ExternalPort"
	if [ -z "$ex_port" -o "$ex_port" = "0" ]; then
		IFS=":" read -r proto port_range <<EOM
$port
EOM
		IFS="-" read -r start_port end_port <<EOM
$port_range
EOM
		setm="${setm:+$setm	}${pmap_obj}.Protocol=$proto"
		setm="${setm:+$setm	}${pmap_obj}.ExternalPort=$start_port"
		setm="${setm:+$setm	}${pmap_obj}.ExternalPortEndRange=${end_port:-0}"
		cmclient -v setm_out SETM "${setm}"
	else
		. /etc/clish/quick_cm.sh list_add "${pmap_obj}".${prefix}AdditionalExternalPort "${port}"
	fi
	setm=""
}
in_traffic_del_external_port() {
	local pmap_obj="$1"
	local port="$2"
	local prefix="$3"
	cmclient -v a GETV ${pmap_obj}.ExternalPort
	if [ -n "$a" -a "$a" != "0" ]; then
		cmclient -v proto GETV ${pmap_obj}.Protocol
		cmclient -v b GETV ${pmap_obj}.ExternalPortEndRange
		[ "$b" = "0" ] && b=
		out="$proto:${a}${b:+-$b}"
		if [ "$out" = "$port" ]; then
			cmclient -v new_ports GETV ${pmap_obj}.${prefix}AdditionalExternalPort
			in_traffic_set_external_port ${pmap_obj} "$new_ports" "$prefix"
		else
			. /etc/clish/quick_cm.sh list_del "${pmap_obj}".${prefix}AdditionalExternalPort "$port"
		fi
	fi
}
in_traffic_set_external_port() {
	local pmap_obj="$1"
	local ports="$2"
	local prefix="$3"
	local port proto port_range setm additional_external_port setm_extra
	set -f
	IFS=","
	set -- $ports
	unset IFS
	set +f
	IFS=":" read -r proto port_range <<EOM
$1
EOM
	IFS="-" read -r a b <<EOM
$port_range
EOM
	setm="${setm:+$setm	}${pmap_obj}.Protocol=${proto:-TCP}"
	setm="${setm:+$setm	}${pmap_obj}.ExternalPort=${a:-0}"
	setm="${setm:+$setm	}${pmap_obj}.ExternalPortEndRange=${b:-0}"
	shift
	for port; do
		additional_external_port="${additional_external_port:+$additional_external_port,}$port"
	done
	setm_extra="${additional_external_port:+${pmap_obj}.${prefix}AdditionalExternalPort=$additional_external_port}"
	cmclient -v setm_out SETM "${setm}	${setm_extra:-${pmap_obj}.${prefix}AdditionalExternalPort=""}"
}
in_traffic_show_external_port() {
	local pmap_obj="$1"
	local show="$2"
	local prefix="$3"
	local out a b proto s
	cmclient -v proto GETV ${pmap_obj}.Protocol
	if [ "$proto" = "ICMP" -o "$proto" = "X_ADB_GRE" ]; then
		out="${proto#$prefix}"
		[ "$show" != "true" ] && printf "$out\n"
	else
		cmclient -v a GETV ${pmap_obj}.ExternalPort
		if [ -n "$a" -a "$a" != "0" ]; then
			cmclient -v b GETV ${pmap_obj}.ExternalPortEndRange
			[ "$b" = "0" ] && b=
			out="${proto#$prefix}:${a}${b:+-$b}"
			cmclient -v s GETV ${pmap_obj}.${prefix}AdditionalExternalPort
			set -f
			IFS=","
			set -- $s
			unset IFS
			set +f
			for p; do
				if [ "$show" = "true" ]; then
					out="$out,$p"
				else
					out="${out#$prefix}\n${p#$prefix}"
				fi
			done
		fi
		[ "$show" != "true" ] && printf "$out\n" || printf "$out"
	fi
}
show_interfaces() {
	local obj rw i objAccess role
	get_user_role role
	for obj in $@; do
		get_obj_access_for_role objAccess "$obj" 3 "$role"
		[ $objAccess -ge 1 ] || continue
		echo
		echo "$(tr_to_cli $obj):"
		print_horizontal_line
		for i in Enable Status Alias X_ADB_Type; do
			show_from_cm "$obj" "$i"
		done
		print_2_col_row "Interface" "$(tr_to_cli $(ip_interface_get_cli_ll $(cmclient GETV $obj.Interface)))"
		cmclient -v i GETV "$obj.X_ADB_ForwardingPolicy"
		if [ "$i" != "-1" ]; then
			local qos
			cmclient -v qos GETO "Device.QoS.Classification.[ForwardingPolicy=$i]"
			print_2_col_row "Forwarding Policy" "$(tr_to_cli $qos)"
		else
			print_2_col_row "Forwarding Policy" "Not used"
		fi
		local ip_addr
		local ip_mask=""
		local port_start
		local port_end
		cmclient -v port_start GETV $obj.X_ADB_ExternalPort
		cmclient -v port_end GETV $obj.X_ADB_ExternalPortEndRange
		cmclient -v ip_addr GETV $obj.X_ADB_ExternalIPAddress
		if [ -z "$ip_addr" ]; then
			local ip_if
			cmclient -v ip_if GETV $obj.Interface
			cmclient -v ip_addr GETV $ip_if.IPv4Address.IPAddress
			ip_addr=$(list_to_comma_sep $ip_addr)
		fi
		if [ -n "$ip_addr" ]; then
			cmclient -v ip_mask GETV $obj.X_ADB_ExternalIPMask
		else
			ip_addr="Default"
		fi
		if [ -z "$ip_mask" ]; then
			ip_mask="255.255.255.255"
		fi
		if [ -z "$port_start" -o "$port_start" = "0" ]; then
			port_start="All ports"
			port_end=""
		fi
		if [ "$port_end" = "0" ]; then
			port_end=""
		fi
		print_2_col_row "External IP Address" "$ip_addr"
		print_2_col_row "External IP Mask" "$ip_mask"
		print_2_col_row "External Port" "$port_start"
		print_2_col_row "External Port End Range" "$port_end"
		print_horizontal_line
	done
	echo
}
nat_interface() {
	local cmd="$1"
	local ip_obj="$2"
	local nat_objs=""
	local idx
	local nat_obj=""
	local hidden_objs=""
	local rw=""
	local role
	local objAccess
	get_user_role role
	cmclient -v nat_objs GETO Device.NAT.InterfaceSetting.[Interface="$ip_obj"]
	for nat_obj in $nat_objs; do
		get_obj_access_for_role objAccess "$nat_obj" 3 "$role"
		[ $objAcces -ge 2 ] && continue
		hidden_objs="$hidden_objs $nat_obj"
	done
	if [ "$cmd" = "enable" -a -z "$hidden_objs" ]; then
		cmclient -v idx ADD Device.NAT.InterfaceSetting
		nat_objs="$nat_objs Device.NAT.InterfaceSetting.$idx"
		cmclient SET "Device.NAT.InterfaceSetting.$idx.Interface $ip_obj" >/dev/null
	fi
	for nat_obj in $nat_objs; do
		case "$cmd" in
		enable)
			cmclient SET "$nat_obj.Enable true" >/dev/null
			;;
		disable)
			cmclient SET "$nat_obj.Enable false" >/dev/null
			;;
		esac
	done
}
translate_external_port_parameter_name() {
	local external_port_list="$1" result port
	case "$external_port_list" in
	*,*)
		IFS=","
		for port in $external_port_list; do
			case "$port" in
			TCPUDP*)
				result="${result:+$result,}X_ADB_$port"
				;;
			*)
				result="${result:+$result,}$port"
				;;
			esac
		done
		unset IFS
		;;
	*)
		case "$external_port_list" in
		TCPUDP*)
			result="X_ADB_$external_port_list"
			;;
		*)
			result="$external_port_list"
			;;
		esac
		;;
	esac
	echo "$result"
}
OBJ="$(cli_or_tr_alias_to_tr_obj $2)"
case "$1" in
clear)
	cmclient -v obj GETO "Device.NAT.PortMapping"
	for arg in $obj; do
		if [ -n "$2" ]; then
			if [ "$(tr_to_cli $arg)" = "$2" ]; then
				cmclient DEL "$arg" >/dev/null
				break
			fi
		else
			cmclient DEL "$arg" >/dev/null
		fi
	done
	;;
show)
	show "$2"
	;;
enable)
	local status obj arg
	cmclient -v obj GETO "Device.NAT.PortMapping"
	status=$3
	if [ -n "$status" -a -n "$2" ]; then
		for arg in $obj; do
			if [ "$(tr_to_cli $arg)" = "$2" ]; then
				cmclient SET "${arg}.Enable" "$status" >/dev/null
				break
			fi
		done
	fi
	;;
interface)
	ip_obj=$(ll_obj_to_ip_obj $(cli_or_tr_alias_to_tr_obj "$3"))
	if [ -n "$ip_obj" ]; then
		nat_interface "$2" "$ip_obj"
	else
		die "ERROR: no nat for $3"
	fi
	;;
interface_show)
	cmclient -v objs GETO Device.NAT.InterfaceSetting
	show_interfaces "$objs"
	;;
interface_show_entry)
	show_interfaces "$OBJ"
	;;
fwd_delete)
	cmclient -v fp GETV "$OBJ.X_ADB_ForwardingPolicy"
	if [ "$fp" != "-1" ]; then
		cmclient -v qos GETO "Device.QoS.Classification.[ForwardingPolicy=$fp]"
		[ -n "$qos" ] && cmclient DEL "$qos" >/dev/null
		setm="$OBJ.X_ADB_ForwardingPolicy=-1"
	fi
	;;
"in_traffic_add_external_port")
	in_traffic_add_external_port "$2" "$3" "$4" "$5" "$6"
	;;
"in_traffic_del_external_port")
	in_traffic_del_external_port "$2" "$3" "$4"
	;;
"in_traffic_set_external_port")
	in_traffic_set_external_port "$2" "$3" "$4"
	;;
"in_traffic_show_external_port")
	in_traffic_show_external_port "$2" "$3" "$4"
	;;
*)
	[ -n "$1" ] && setm="$OBJ.$1=$3"
	;;
esac
[ -n "$setm" ] && exec /etc/clish/quick_cm.sh setm "${setm}" || :
