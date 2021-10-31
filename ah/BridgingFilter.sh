#!/bin/sh
AH_NAME="BridgingFilter"
EBTABLE_NAME="nat"
EBCHAIN_NAME="BridgeFilter"
EBLINK_NAME="PREROUTING"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "yacs" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
PRI_ebtables_rule_number() {
	local _order="$1" enabled_rules_list i
	order=1
	cmclient -v enabled_rules_list GETV "Bridging.Filter.*.[Status=Enabled].Order"
	for i in $enabled_rules_list; do
		[ $i -lt $_order ] && order=$((order + 1))
	done
}
PRI_ebtables_match() {
	local eb_match _eb_vlanopt _eb_dhcpopt _sd
	PRI_dhcp_options _eb_dhcpopt
	while true; do
		eb_match=""
		PRI_ethertype_option
		PRI_sourceaddress_option
		PRI_destaddress_option
		[ -z "$eb_match" ] && [ -n "$_sd" ] && break
		_sd="true"
		eb_match="${_eb_vlanopt} ${eb_match} -i ${if_name} ${_eb_dhcpopt}"
		ebtables -t $EBTABLE_NAME -A $FICHAIN_NAME $eb_match -j ACCEPT
	done
}
PRI_ethertype_option() {
	local item eb_protocol
	if [ -n "$br_ether" ]; then
		item="${br_ether%%,*}"
		[ -z "$_eb_vlanopt" ] && eb_match=$eb_match" -p " || eb_match=$eb_match" --vlan-encap "
		[ "$newEthertypeFilterExclude" = "true" ] && eb_match=$eb_match" ! "
		eb_protocol=$(printf "0x%04x" "$item")
		eb_match=$eb_match"$eb_protocol"
		[ "$br_ether" = "$item" ] && br_ether="" || br_ether="${br_ether#*,}"
	fi
}
PRI_sourceaddress_option() {
	local item
	if [ -n "$br_source" ]; then
		item="${br_source%%,*}"
		eb_match=$eb_match" -s "
		[ "$newSourceMACAddressFilterExclude" = "true" ] && eb_match=$eb_match" ! "
		eb_match=$eb_match"$item"
		[ "$br_source" = "$item" ] && br_source="" || br_source="${br_source#*,}"
	fi
}
PRI_destaddress_option() {
	local item
	if [ -n "$br_dest" ]; then
		item="${br_dest%%,*}"
		eb_match=$eb_match" -d "
		[ "$newDestMACAddressFilterExclude" = "true" ] && eb_match=$eb_match" ! "
		eb_match=$eb_match"$item"
		[ "$br_dest" = "$item" ] && br_dest="" || br_dest="${br_dest#*,}"
	fi
}
PRI_dhcp_options() {
	local br_dhcp_tag br_dhcp_value br_dhcp_timeout br_dhcp_flags br_exclude \
		_match1 _match2 _match_mode \
		filter_value filter_exclude filter_flag
	[ "$1" != "_dhcp_opt" ] && local _dhcp_opt
	br_dhcp_timeout=${newX_ADB_Timeout-0}
	if [ -n "$newSourceMACFromVendorClassIDFilter" ]; then
		_match1="Source"
		_match2="VendorClassID"
	elif [ -n "$newDestMACFromVendorClassIDFilter" ]; then
		_match1="Dest"
		_match2="VendorClassID"
	elif [ -n "$newSourceMACFromClientIDFilter" ]; then
		_match1="Source"
		_match2="ClientID"
	elif [ -n "$newDestMACFromClientIDFilter" ]; then
		_match1="Dest"
		_match2="ClientID"
	elif [ -n "$newSourceMACFromUserClassIDFilter" ]; then
		_match1="Source"
		_match2="UserClassID"
	elif [ -n "$newDestMACFromUserClassIDFilter" ]; then
		_match1="Dest"
		_match2="UserClassID"
	fi
	eval _match_mode=\$new${_match1}MACFrom${_match2}Mode
	case "$_match_mode" in
	"Substring") _match_mode="substr" ;;
	"Prefix") _match_mode="prefix" ;;
	"Suffix") _match_mode="suffix" ;;
	"Exact") _match_mode="" ;;
	*) _match_mode="" ;;
	esac
	case "$_match2" in
	"VendorClassID")
		br_dhcp_tag="60"
		;;
	"ClientID")
		br_dhcp_tag="61"
		_match_mode="hex"
		;;
	"UserClassID")
		br_dhcp_tag="77"
		_match_mode="hex"
		;;
	*)
		return
		;;
	esac
	eval filter_value=\$new${_match1}MACFrom${_match2}Filter
	eval filter_exclude=\$new${_match1}MACFrom${_match2}FilterExclude
	eval new${_match1}MACFrom${_match2}Filter=""
	br_dhcp_value=${filter_value}
	[ "$filter_exclude" = "true" ] && br_exclude="!"
	[ "$_match1" = "Source" ] && br_dhcp_flags="src" || br_dhcp_flags="dst"
	[ -n "$_match_mode" ] && br_dhcp_flags="${br_dhcp_flags},${_match_mode}"
	_dhcp_opt=" -l dhcp --dhcp-tag $br_dhcp_tag $br_exclude --dhcp-value $br_dhcp_value --dhcp-timeout $br_dhcp_timeout --dhcp-flags $br_dhcp_flags"
	eval $1='$_dhcp_opt'
}
PRI_vlanid_option() {
	[ "$newVLANIDFilter" = "0" ] && return
	eval $1=\"-p 8021Q --vlan-id $newVLANIDFilter\"
}
PRI_boolean_array() {
	local newSourceMACAddressFilterList2 newDestMACAddressFilterList2 newEthertypeFilterList2
	newEthertypeFilterList2="$newEthertypeFilterList"
	while [ 1 ]; do # newEthertypeFilterList
		newDestMACAddressFilterList2="$newDestMACAddressFilterList"
		while [ 1 ]; do # newDestMACAddressFilterList
			newSourceMACAddressFilterList2="$newSourceMACAddressFilterList"
			while [ 1 ]; do # newSourceMACAddressFilterList
				[ -n "$newSourceMACAddressFilterList2" ] &&
					br_source="${newSourceMACAddressFilterList2%%,*},$br_source"
				[ -n "$newDestMACAddressFilterList2" ] &&
					br_dest="${newDestMACAddressFilterList2%%,*},$br_dest"
				[ -n "$newEthertypeFilterList2" ] &&
					br_ether="${newEthertypeFilterList2%%,*},$br_ether"
				if [ "$newSourceMACAddressFilterList2" = "${newSourceMACAddressFilterList2#*,}" ]; then
					newSourceMACAddressFilterList2=""
					break
				else
					newSourceMACAddressFilterList2="${newSourceMACAddressFilterList2#*,}"
				fi
			done
			if [ "$newDestMACAddressFilterList2" = "${newDestMACAddressFilterList2#*,}" ]; then
				newDestMACAddressFilterList2=""
				break
			else
				newDestMACAddressFilterList2="${newDestMACAddressFilterList2#*,}"
			fi
		done
		if [ "$newEthertypeFilterList2" = "${newEthertypeFilterList2#*,}" ]; then
			newEthertypeFilterList2=""
			break
		else
			newEthertypeFilterList2="${newEthertypeFilterList2#*,}"
		fi
	done
}
ebtables_init() {
	local command="$1" eb_operation hw_switch
	if [ "$command" = "start" ]; then
		eb_operation="-A"
		hw_switch="Disable"
	elif [ "$command" = "stop" ]; then
		eb_operation="-D"
		hw_switch="Enable"
	fi
	ebtables -t $EBTABLE_NAME $eb_operation $EBLINK_NAME -j $EBCHAIN_NAME
	cmclient SET Device.Bridging.X_ADB_HWSwitch.${hw_switch}Request "BridgingFilter"
}
ebwrap_retrievevars() {
	local _tmp _vlan_id _suffix
	help_lowlayer_ifname_get if_name "$newInterface"
	cmclient -v _tmp GETV "${newInterface}.X_ADB_FakePort"
	[ "$_tmp" = "true" ] && cmclient -v _suffix GETV "${newBridge}.Port.[ManagementPort=true].Name" && _suffix="_"$_suffix
	cmclient -v _tmp GETV "${newBridge}.VLANPort.[Port=${newInterface}].[Untagged=false].VLAN"
	[ -n "$_tmp" ] && cmclient -v _vlan_id GETV "$_tmp.VLANID" && _vlan_id="."$_vlan_id
	if_name=$if_name$_vlan_id$_suffix
}
ebtables_wrapper() {
	local command="$1" order if_name FICHAIN_NAME="BF_${obj##Device.Bridging.}"
	if [ "$command" = "add" ]; then
		ebwrap_retrievevars
		local br_source br_dest br_ether
		PRI_boolean_array
		PRI_ebtables_rule_number "$newOrder"
		ebtables -t nat -N $FICHAIN_NAME -P RETURN
		ebtables -t $EBTABLE_NAME -I $EBCHAIN_NAME $order -j $FICHAIN_NAME
		PRI_ebtables_match
	elif [ "$command" = "del" ]; then
		ebtables -t $EBTABLE_NAME -D $EBCHAIN_NAME -j $FICHAIN_NAME
		ebtables -t $EBTABLE_NAME -F $FICHAIN_NAME
		ebtables -t $EBTABLE_NAME -X $FICHAIN_NAME
	else
		return 1
	fi #----------------------------------------------#
}   ###########################
BF_reorder() {
	local operation="$1" order="$2" obj_order i
	cmclient -v i GETO "Bridging.Filter"
	for i in $i; do
		[ "$obj" = "$i" ] && continue
		cmclient -v obj_order GETV "$i.Order"
		if [ $obj_order -ge $order ]; then
			if [ "$operation" = "add" ]; then
				obj_order=$((obj_order + 1))
			elif [ "$operation" = "del" ]; then
				obj_order=$((obj_order - 1))
			else
				return 1
			fi
			cmclient SETE "$i.Order" "$obj_order"
		fi
	done
}
count_bf() {
	local i cnt=0
	cmclient -v i GETO Bridging.Filter.*.[Enable=true]
	for i in $i; do cnt=$((cnt + 1)); done
	eval $1='$cnt'
}
service_delete() {
	local bfe_number
	case "$obj" in
	"Device.Bridging.Filter."*)
		BF_reorder "del" "$newOrder"
		[ "$newEnable" = "false" ] && exit 0
		ebtables_wrapper "del"
		count_bf bfe_number
		[ $bfe_number -eq 1 ] && ebtables_init "stop"
		;;
	esac
}
service_add() {
	case "$obj" in
	"Device.Bridging.Filter."*)
		local bfe_number
		cmclient -v bfe_number GETV Device.Bridging.FilterNumberOfEntries
		cmclient SETE "$obj.Order" "$bfe_number"
		;;
	esac
}
BF_set_Enable() {
	local bfe_number
	reconf_needed="true"
	count_bf bfe_number
	if [ "$newEnable" = "false" ]; then
		cmclient SETE "${obj}.Status" "Disabled"
		[ $bfe_number -eq 0 ] && ebtables_init "stop"
	else ###  Object switched on
		cmclient SETE "${obj}.Status" "Enabled"
		[ $bfe_number -eq 1 ] && ebtables_init "start"
	fi
}
BF_set_Order() {
	reconf_needed="true"
	BF_reorder "del" "$oldOrder"
	BF_reorder "add" "$newOrder"
}
BF_set_Status() {
	local _switch_off="false" _switch_on="false"
	case "$newStatus" in
	"Error_Misconfigured")
		cmclient SETE "${obj}.Interface" ""
		cmclient SETE "${obj}.Bridge" ""
		[ "$oldStatus" = "Enabled" ] && _switch_off="true"
		;;
	"Disabled")
		[ "$oldStatus" = "Enabled" ] && _switch_off="true"
		;;
	"Enabled")
		_switch_on="true"
		;;
	esac
	if [ "$newEnable" = "true" ]; then
		if [ "$_switch_off" = "true" ]; then
			reconf_needed="true"
			newEnable="false"
		elif [ "$_switch_on" = "true" ]; then
			reconf_needed="true"
			oldEnable="false"
		fi
	fi
}
service_config() {
	if [ "$user" = "init" ]; then
		ebtables_wrapper "add"
		exit 0
	fi ### ###
	reconf_needed="false"
	[ $changedEnable -eq 1 ] && BF_set_Enable
	[ $changedOrder -eq 1 ] && BF_set_Order
	[ $changedStatus -eq 1 ] && BF_set_Status
	help_is_changed Bridge Interface VLANIDFilter \
		SourceMACAddressFilterList SourceMACAddressFilterExclude \
		DestMACAddressFilterList DestMACAddressFilterExclude \
		SourceMACFromClientIDFilter SourceMACFromClientIDFilterExclude \
		DestMACFromClientIDFilter DestMACFromClientIDFilterExclude \
		SourceMACFromUserClassIDFilter SourceMACFromUserClassIDFilterExclude \
		DestMACFromUserClassIDFilter DestMACFromUserClassIDFilterExclude \
		SourceMACFromVendorClassIDFilter SourceMACFromVendorClassIDFilterExclude \
		DestMACFromVendorClassIDFilter DestMACFromVendorClassIDFilterExclude \
		SourceMACFromVendorClassIDMode DestMACFromVendorClassIDMode \
		EthertypeFilterList EthertypeFilterExclude &&
		reconf_needed="true"
	if [ "$reconf_needed" = "true" ]; then
		[ "$oldEnable" = "true" ] && ebtables_wrapper "del"
		[ "$newEnable" = "true" ] && ebtables_wrapper "add"
	fi
}
if [ $# -eq 1 ] && [ "$1" = "init" ]; then
	cmclient -v lobj GETO Device.Bridging.Filter.[Enable=true]
	[ ${#lobj} -eq 0 ] && return
	ebtables_init "start"
	for lobj in $lobj; do
		cmclient SET "$lobj".Status "Enabled"
	done
fi
case "$op" in
"a")
	service_add
	;;
"d")
	service_delete
	;;
"s")
	service_config
	;;
esac
exit 0
