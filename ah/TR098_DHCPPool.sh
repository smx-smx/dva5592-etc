#!/bin/sh
AH_NAME="DHCPPool"
[ "$user" = "cm181" ] && exit 0
[ "$user" = "$AH_NAME" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
service_lookup_param() {
	local _tr098obj="$1"
	local _tr098par="$2"
	local _tr181=""
	tr181obj=""
	param181=""
	case "$_tr098par" in
	"Enable")
		tr181obj="$found_obj"
		;;
	"LocallyServed")
		_tr181="LocallyServed"
		;;
	"SourceInterface")
		_tr181="Interface"
		tr181obj=$(cmclient GETO "Device.IP.Interface.*.[$PARAM_TR098>${_tr098obj%.DHCP*}]")
		;;
	"UseAllocatedWAN")
		assoc_conn=$(cmclient GETV "$_tr098obj.AssociatedConnection")
		_tr181="PassthroughEnable"
		if [ -n "$assoc_conn" ]; then
			case "$assoc_conn" in
			*"WANPPPConnection"*)
				ppp_obj=$(cmclient GETO "Device.PPP.Interface.*.[$PARAM_TR098=$assoc_conn]")
				if [ -n "$ppp_obj" ]; then
					tr181obj="$ppp_obj.IPCP"
				fi
				;;
			*"WANIPConnection"*)
				ip_obj=$(cmclient GETO "Device.IP.Interface.*.[$PARAM_TR098=$assoc_conn]")
				dhcp_obj=$(cmclient GETO "Device.DHCPv4.Client.*.[Interface=$ip_obj]")
				if [ -n "$dhcp_obj" ]; then
					tr181obj="$dhcp_obj"
				fi
				;;
			esac
		fi
		;;
	*) ;;

	esac
	param181="$_tr181"
}
service_set_param() {
	local obj98="$1"
	local param98="$2"
	local _val="$3"
	service_lookup_param "$obj98" "$param98"
	case $param98 in
	"Enable")
		found_if=$(cmclient GETV $tr181obj.Interface)
		if [ -z "$found_if" ]; then
			l2="${obj98%.*}"
			l2="${l2%.*}"
			buffer="$obj98.SourceInterface=$l2"
		fi
		if [ -z "$buffer" ]; then
			buffer="$tr181obj.$param98=$_val"
		else
			buffer="$buffer	$tr181obj.$param98=$_val"
		fi
		;;
	"LocallyServed")
		poolif=$(cmclient GETV "$found_obj.Interface")
		if [ -n "$poolif" ]; then
			tr181relay=$(cmclient GETO "Device.DHCPv4.Relay.Forwarding.*.[Interface=$poolif]")
		fi
		for o in $tr181relay; do
			if [ "$_val" = "false" ]; then
				for param_couple in $(cmclient GET "$obj98."); do
					set -f
					IFS=";"
					set -- $param_couple
					unset IFS
					set +f
					_param98=$1
					val=$2
					_param="${_param98##*.}"
					case "$_param" in
					"DHCPLeaseTime" | "DNSServers" | "DomainName" | "IPRouters" | \
						"X_ADB_TR181Name" | "MaxAddress" | "MinAddress" | \
						"ReservedAddresses" | "SubnetMask" | "UseAllocatedWAN" | "AssociatedConnection")
						continue
						;;
					"DHCPServerIPAddress")
						param181="DHCPServerIPAddress"
						;;
					*)
						service_lookup_param "$_param98" "$val"
						if [ -n "$param181" ]; then
							case "$param181" in
							"Normal")
								val="false"
								;;
							"Passthrough")
								val="true"
								;;
							esac
						fi
						;;
					esac
					if [ -n "$val" ] && [ -n "$param181" ]; then
						if [ -z "$buffer" ]; then
							buffer="$o.$param181=$val"
						else
							buffer="$buffer	$o.$param181=$val"
						fi
					fi
				done
			fi
			if [ -z "$buffer" ]; then
				buffer="$o.$param98=$_val"
			else
				buffer="$buffer	$o.$param98=$_val"
			fi
		done
		;;
	"SourceInterface")
		if [ -n "$_val" ]; then
			set -f
			IFS=","
			set -- $_val
			unset IFS
			set +f
			for arg; do
				tr181obj=$(cmclient GETO "Device.IP.Interface.*.[$PARAM_TR098>${arg%.DHCP*}]")
				for o in $tr181obj; do
					o_181ref=$(cmclient GETV $o.$PARAM_TR098)
					if [ -n "$o_181ref" ]; then
						if [ -z "$buffer" ]; then
							buffer="$found_obj.Interface=$o"
						else
							buffer="$buffer	$found_obj.Interface=$o"
						fi
					fi
				done
			done
		else
			tr181obj=$(cmclient GETO "Device.IP.Interface.*.[$PARAM_TR098=${obj98%.DHCP*}]")
			if [ -n "$tr181obj" ]; then
				o_181ref=$(cmclient GETV $tr181obj.$PARAM_TR098)
				if [ -n "$o_181ref" ]; then
					if [ -z "$buffer" ]; then
						buffer="$found_obj.Interface=$tr181obj"
					else
						buffer="$buffer	$found_obj.Interface=$tr181obj"
					fi
				fi
			fi
		fi
		;;
	"UseAllocatedWAN")
		if [ "$_val" = "Passthrough" ]; then
			buffer="$tr181obj.PassthroughEnable=true	$tr181obj.PassthroughDHCPPool=$found_obj"
		else
			buffer="$tr181obj.PassthroughEnable=false"
		fi
		;;
	*) ;;

	esac
	if [ -z "$setm_params" ]; then
		setm_params="$buffer"
	else
		setm_params="$setm_params	$buffer"
	fi
}
service_config() {
	setm_params=""
	for i in Enable LocallyServed SourceInterface UseAllocatedWAN; do
		if eval [ \${set${i}:=0} -eq 1 ]; then
			eval service_set_param "$obj" "$i" \"\$new${i}\"
		fi
	done
	if [ -n "$setm_params" ]; then
		cmclient -u "tr098" SETM "$setm_params" >/dev/null
	fi
}
service_get() {
	local obj98="$1"
	local param98="$2"
	local value98=""
	service_lookup_param "$obj98" "$param98"
	if [ -n "$param181" ]; then
		case "$param181" in
		"PassthroughEnable")
			value98="Normal"
			if [ -n "$tr181obj" ]; then
				value181=$(cmclient GETV "$tr181obj.PassthroughEnable")
				if [ "$value181" = "true" ]; then
					value98="Passthrough"
				fi
			fi
			;;
		esac
	fi
	echo "$value98"
}
service_add() {
	setm_params=""
	found_obj=$(help98_add_tr181obj "$obj" "Device.DHCPv4.Server.Pool")
	cmclient SET "$obj.$PARAM_TR181" "$found_obj" >/dev/null
	tr098if="${obj%.*}"
	tr098if="${tr098if%.*}"
	service_set_param "$obj" "SourceInterface" "$tr098if"
	if [ -n "$setm_params" ]; then
		cmclient -u "tr098" SETM "$setm_params" >/dev/null
	fi
}
tr181obj=""
param181=""
case "$op" in
"a")
	service_add
	;;
"d")
	local found_obj=$(cmclient GETV "$obj.X_ADB_TR181Name")
	if [ -n "$found_obj" ]; then
		help181_del_object "$found_obj"
	fi
	;;
"g")
	local found_obj=$(cmclient GETV "$obj.X_ADB_TR181Name")
	if [ -n "$found_obj" ]; then
		for arg; do # Arg list as separate words
			service_get "$obj" "$arg"
		done
	else
		for arg; do # Arg list as separate words
			echo ""
		done
	fi
	;;
"s")
	local found_obj=$(cmclient GETV "$obj.X_ADB_TR181Name")
	if [ -n "$found_obj" ]; then
		service_config
	fi
	;;
esac
exit 0
