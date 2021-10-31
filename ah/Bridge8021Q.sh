#!/bin/sh
. /etc/ah/Bridge8021Q_Port.sh
. /etc/ah/Bridge8021Q_VLAN.sh
. /etc/ah/Bridge8021Q_VLANPort.sh
. /etc/ah/helper_bridge.sh
. /etc/ah/helper_mtu.sh
command -v help_ipv6_reconf_iface >/dev/null || . /etc/ah/IPv6_helper_functions.sh
BRIDGE_PREFIX="br"
VLAN_PREFIX="_v"
service_delete_8021Q() {
	if [ -n "$is_VLANPort" ]; then
		echo "### "$AH_NAME"(802.1Q): DELETE VLANPort  ###"
		service_delete_8021Q_vlanport
	elif [ -n "$is_VLAN" ]; then
		echo "### "$AH_NAME"(802.1Q): DELETE VLAN  ###"
		service_delete_8021Q_vlan
	elif [ -n "$is_port" ]; then
		echo "### "$AH_NAME"(802.1Q): DELETE Port  ###"
		service_delete_8021Q_port
	fi
}
find_matching_lowlayer() {
	local _p=$2 _no=$1 _o _tmp
	IFS=','
	while [ ${#_no} -gt 0 ]; do
		_o=$_no
		unset _no
		for _o in $_o; do
			case $_o in
			"$_p" | "$_p".*)
				unset IFS
				return 0
				;;
			esac
			cmclient -v _tmp GETV $_o.LowerLayers
			[ ${#_tmp} -gt 0 ] && _no=${_no:+$_no,}$_tmp
		done
	done
	unset IFS
	return 1
}
SRV_8021Q_check_fake_interface() {
	local _command="$1" _port_obj="$2" fk_check=0 _fk _upper _ll
	cmclient -v _fk GETV "${_port_obj}.X_ADB_FakePort"
	if [ "$_fk" = "true" ]; then
		fk_check=1
		[ "$_command" != "add" ] && cmclient SETE "${_port_obj}.X_ADB_FakePort" "false"
	elif [ "$_command" = "add" ]; then
		if [ -n "$3" -a "$4" = "false" ]; then
			cmclient -v _ll GETV $_port_obj.LowerLayers
			cmclient -v _upper GETV "Ethernet.VLANTermination.[VLANID=$3].LowerLayers"
			if find_matching_lowlayer "$_upper" "$_ll"; then
				cmclient SETE $_port_obj.X_ADB_FakePort true
				fk_check=1
			fi
			return $fk_check
		fi
		if is_wan_intf $_port_obj; then
			cmclient SETE "$_port_obj.X_ADB_FakePort" "true"
			return 1
		fi
		cmclient -v _upper GETV "InterfaceStack.[LowerLayer=%($_port_obj.LowerLayers)].HigherLayer"
		for _upper in $_upper; do
			[ "$_upper" = "$_port_obj" ] && continue
			case $_upper in
			Device.Bridging.Bridge.*.Port.*)
				cmclient -v _upper GETO $_upper.[Enable=true].[X_ADB_FakePort!true]
				;;
			*)
				cmclient -v _upper GETO $_upper.[Enable=true]
				;;
			esac
			if [ ${#_upper} -gt 0 ]; then
				cmclient SETE "${_port_obj}.X_ADB_FakePort" "true"
				return 1
			fi
		done
	fi
	return $fk_check
}
SRV_8021Q_create_vlaniface() {
	local _command="$1" _viface="$2" _vlan_id="$3"
	if [ "$_command" = "add" ]; then
		[ -d /sys/class/net/$_interface.$_vlan_id ] && return
		vconfig add $_viface $_vlan_id
		ipv6_proc_enable "false" "$iface"
		SRV_8021Q_change_interface_status "$_viface.$_vlan_id" "Up"
	else # Remove interface
		[ ! -d /sys/class/net/$_interface.$_vlan_id ] && return
		SRV_8021Q_change_interface_status "$_viface.$_vlan_id" "Down"
		vconfig rem $_viface.$_vlan_id
	fi
}
SRV_8021Q_create_vlanbridge() {
	local _command="$1" _vbridge="$2" _type="$3" _ebtables_cmd
	local _vlan_id="${4:-${_vbridge#*$VLAN_PREFIX}}"
	[ "$_vbridge" = "$_vlan_id" ] && _vlan_id="0"
	if [ "$_command" = "add" ]; then
		echo "### $AH_NAME: Executing <brctl addbr $_vbridge> ###"
		help_add_bridge "$_type" "$_vbridge"
		SRV_8021Q_change_interface_status "$_vbridge" "Up"
		_ebtables_cmd="A"
	elif [ "$_command" = "rem" ]; then
		SRV_8021Q_change_interface_status "$_vbridge" "Down"
		echo "### $AH_NAME: Executing <brctl delbr $_vbridge> ###"
		help_del_bridge "$_type" "$_vbridge"
		_ebtables_cmd="D"
	else
		echo "### $_AH_NAME: service_vlanbridge_cmd() COMMAND ERROR!"
		echo "### $_AH_NAME: VLAN Bridge NOT CREATED"
	fi
	if [ "$_vlan_id" != "0" ]; then
		ebtables -t broute -$_ebtables_cmd BROUTING -p 802_1Q --vlan-id $_vlan_id -j DROP
	fi
}
SRV_8021Q_iface_to_bridge() {
	local _command="$1" _bridge_obj="$2" _port_obj=$3 iface="$4"
	local _vlanid="$5" _ingressfiltering="$6" _untagged="$7"
	local cmd="" temp="" bridge="" bridge_type=""
	temp=$((${_bridge_obj##*Bridge.} - 1)) # bridge number
	bridge="$BRIDGE_PREFIX$temp"           # e.g. br0
	cmclient -v bridge_type GETV "$_bridge_obj.X_ADB_BridgeType"
	if [ "$_ingressfiltering" = "true" ]; then
		bridge="$bridge""$VLAN_PREFIX""$_vlanid" #e.g. br0_v10
	fi
	if [ "$_command" = "add" ]; then
		cmd="addif"
		! ip link show dev "$bridge" && SRV_8021Q_create_vlanbridge "add" "$bridge" "$bridge_type" ""
	else
		cmd="delif"
	fi
	if is_wan_intf $_port_obj; then
		ebtables -D IGMPlan -o $iface -j RETURN
		ebtables -D IGMPlan -i $iface -j RETURN
		if [ "$cmd" = "addif" ]; then
			ebtables -I IGMPlan -o $iface -j RETURN
			ebtables -I IGMPlan -i $iface -j RETURN
		fi
	fi
	echo "### $AH_NAME: Executing <brctl $cmd $bridge $iface> ###"
	if [ "$cmd" = "addif" ]; then
		help_add_bridge_port "$bridge_type" "$bridge" "$iface" "${_port_obj##$_bridge_obj.Port.}"
	else
		help_del_bridge_port "$bridge_type" "$bridge" "$iface"
	fi
	cmclient -v _tmp GETV "${_port_obj}.LowerLayers"
	case "$_tmp" in
	*.SSID.*)
		cmclient -v isSSIDEnable GETV "${_tmp}.Enable"
		if [ "$isSSIDEnable" = "true" ]; then
			cmclient SET "${_tmp}.Enable" 'true'
		fi
		;;
	esac
	ipv6_proc_enable "false" "$iface"
	SRV_send_gratuitous_arp "$bridge"
}
SRV_8021Q_populate_bridge() {
	local _command="$1" _bridge_obj="$2" _port_obj="$3" _vlan_obj="$4"
	local _extra_type="$5" _extra_val="$6"
	local _port_ingressfiltering _management_port _management_port_pvid
	local _management_port_infiltering _vlanport _vlanport_untagged
	local _vlan_id _interface all_ports all_vlans check_val skip vlobj
	[ "$_port_obj" = "all" ] && all_ports="1"
	[ "$_vlan_obj" = "all" ] && all_vlans="1"
	if is_wan_intf $_port_obj; then
		SRV_8021D_populate_bridge "$1" "$2" "$_port_obj"
		return
	fi
	cmclient -v vlobj GETO "$_bridge_obj.VLANPort."
	for _vlanport in $vlobj; do
		skip=""
		cmclient -v check_val GETV "$_vlanport".Enable # vlanport.Enable
		if [ "$check_val" != "true" ]; then
			skip="1"
		else
			if [ -n "$all_vlans" ]; then
				cmclient -v _vlan_obj GETV "$_vlanport".VLAN
				cmclient -v check_val GETV "$_vlan_obj".Enable # vlanport.VLAN-->VLAN.Enable
				if [ "$check_val" != "true" ]; then
					skip="1"
				fi
			else
				cmclient -v check_val GETV "$_vlanport".VLAN
				if [ "$check_val" != "$_vlan_obj" ]; then
					skip="1"
				fi
			fi #######################################
			if [ -z "$skip" ]; then
				if [ -n "$all_ports" ]; then
					cmclient -v _port_obj GETV "$_vlanport".Port
					cmclient -v check_val GETV "$_port_obj".Enable # vlanport.Port-->Port.Enable
					if [ "$check_val" != "true" ]; then
						skip="1"
					fi
				else
					cmclient -v check_val GETV "$_vlanport".Port
					if [ "$check_val" != "$_port_obj" ]; then
						skip="1"
					fi
				fi #######################################
			fi
		fi
		if [ -z "$skip" ]; then
			if [ "$_extra_type" = "LowerLayers" ]; then
				help_lowlayer_ifname_get "_interface" "$_extra_val"
			else
				help_lowlayer_ifname_get "_interface" "$_port_obj"
			fi
			[ -z "$_interface" ] && _interface="none"
			if [ "$_extra_type" = "IngressFiltering" ]; then
				_port_ingressfiltering="$_extra_val"
			else
				cmclient -v _port_ingressfiltering GETV "$_port_obj".IngressFiltering
			fi
			if [ "$_extra_type" = "VLANID" ]; then
				_vlan_id="$_extra_val"
			else
				cmclient -v _vlan_id GETV "$_vlan_obj".VLANID
			fi
			if [ "$_extra_type" = "ManagementPortPVID" ]; then
				_management_port_pvid="$_extra_val"
				_management_port_infiltering="true"
			else
				cmclient -v _management_port GETO "$_bridge_obj.Port.*.[ManagementPort=true]"
				cmclient -v _management_port_pvid GETV "$_management_port.PVID"
				cmclient -v _management_port_infiltering GETV "$_management_port.IngressFiltering"
			fi
			if [ "$_management_port_infiltering" = "true" ] && [ "$_vlan_id" = "$_management_port_pvid" ]; then
				_port_ingressfiltering="false" # trick to deal with interfaces in the base bridge
			fi                              #######################
			[ "$_extra_type" = "Untagged" ] && _vlanport_untagged="$_extra_val" ||
				cmclient -v _vlanport_untagged GETV "$_vlanport".Untagged
			if [ "$_vlanport_untagged" = "false" ]; then
				SRV_8021Q_create_vlaniface $_command "$_interface" "$_vlan_id"
				_interface=$_interface.$_vlan_id
			fi
			if ! SRV_8021Q_check_fake_interface "$_command" "$_port_obj" "$_vlan_id" "$_vlanport_untagged"; then
				local _bridge_name
				cmclient -v _bridge_name GETV "${_bridge_obj}.Port.[ManagementPort=true].Name"
				echo "$AH_NAME: $_interface: *($_command)*-> [${_interface}_${_bridge_name}]" >/dev/console
				SRV_8021Q_create_dup_interface "$_command" "${_interface}_${_bridge_name}" "$_interface"
				_interface=${_interface}_${_bridge_name}
				[ "$user" != "init" ] && [ "$_command" = "add" ] && SRV_8021Q_update_filters "${_port_obj}"
			fi
			SRV_8021Q_iface_to_bridge $_command $_bridge_obj $_port_obj $_interface $_vlan_id $_port_ingressfiltering $_vlanport_untagged
			if [ "$_command" = "add" ]; then
				cmclient -v lowlayer GETV "$_port_obj".LowerLayers
				if [ ${lowlayer%.*} = "Device.X_ADB_VPN.GRETap" ]; then
					[ -f /sys/class/net/${_interface%.*}/mtu ] || continue
					read gretap_mtu </sys/class/net/${_interface%.*}/mtu
					ip link set "$_interface" mtu $((gretap_mtu - 4))
				fi
			fi
		fi
	done
}
SRV_8021Q_update_filters() {
	local _port_obj="$1" filter
	cmclient -v filter GETO Device.Bridging.Filter.[Interface=${_port_obj}].[Enable=true]
	for filter in $filter; do
		cmclient SET "${filter}.Status" "Disabled"
		cmclient SET "${filter}.Status" "Enabled"
	done
}
SRV_8021D_populate_bridge() {
	local _command="$1" _bridge_obj="$2" _port_obj="$3" _extra_type="$4" _extra_val="$5"
	local _management_port _interface all_ports check_val check_port skip fk_check pobj _bridge_name lowlayer \
		newX_ADB_MaxMTUSize="" newX_ADB_AutoMTU="" changedX_ADB_AutoMTU=0 setX_ADB_MaxMTUSize=0 changedX_ADB_MaxMTUSize=1
	[ "$_port_obj" = "all" ] && all_ports="1" || check_port="$_port_obj"
	cmclient -v newX_ADB_MaxMTUSize GETV $_bridge_obj.X_ADB_MaxMTUSize
	cmclient -v newX_ADB_AutoMTU GETV $_bridge_obj.X_ADB_AutoMTU
	[ "$newX_ADB_AutoMTU" = "true" ] && changedX_ADB_AutoMTU=1 || setX_ADB_MaxMTUSize=1
	cmclient -v pobj GETO "$_bridge_obj.Port.[ManagementPort=false]"
	for _port_obj in $pobj; do
		skip=""
		if [ -n "$all_ports" ]; then
			cmclient -v check_val GETV "$_port_obj".Enable # Port.Enable
			if [ "$check_val" != "true" ]; then
				skip="1"
			fi
		elif [ "$_port_obj" != "$check_port" ]; then
			skip="1"
		fi
		if [ -z "$skip" ]; then
			if [ "$_extra_type" = "LowerLayers" ]; then
				help_lowlayer_ifname_get "_interface" "$_extra_val"
			else
				help_lowlayer_ifname_get "_interface" "$_port_obj"
			fi
			[ -z "$_interface" ] && _interface="none"
			SRV_8021Q_check_fake_interface "$_command" "$_port_obj"
			fk_check=$?
			if [ $fk_check -eq 1 ]; then
				cmclient -v _bridge_name GETV "${_bridge_obj}.Port.[ManagementPort=true].Name"
				echo "$AH_NAME: $_interface: *($_command)*-> [${_interface}_${_bridge_name}]" >/dev/console
				SRV_8021Q_create_dup_interface "$_command" "${_interface}_${_bridge_name}" "$_interface"
				_interface=${_interface}_${_bridge_name}
				[ "$user" != "init" ] && [ "$_command" = "add" ] && SRV_8021Q_update_filters "${_port_obj}"
			fi
			SRV_8021Q_iface_to_bridge $_command $_bridge_obj $_port_obj $_interface "0" "false" "true"
			if [ "$_command" = "add" ]; then
				cmclient -v lowlayer GETV "$_port_obj".LowerLayers
				help_set_mtu "$lowlayer" "$_port_obj"
			fi
		fi
	done
}
SRV_send_gratuitous_arp() {
	local _iface="$1" _ip_addr _bcast_addr _parse
	local _lock_file="/tmp/arp_"$_iface"_lock"
	[ -f $_lock_file ] && return
	set -- $(ip -o -4 addr show $_iface)
	_ip_addr=${4%%/*}
	_bcast_addr=$6
	[ ${#_ip_addr} -eq 0 ] && return
	case "$_iface" in
	"br"*)
		cmclient -v br_obj GETO Device.Bridging.Bridge.**.[Name="$_iface"]
		br_obj=${br_obj%%".Port"*}
		is_pure_bridge "$br_obj" && return
		;;
	esac
	touch $_lock_file
	(
		sleep 5
		arping -q -c 2 -U -I $_iface -s $_ip_addr $_bcast_addr
		rm $_lock_file
	) &
}
SRV_8021Q_create_dup_interface() {
	local CNET_PATH="/proc/net/cnetdev"
	local _command="$1" _iface_fake="$2" _iface_real="$3" _action
	if [ "$_command" = "add" ]; then
		_action="create"
	else
		_action="delete"
		_iface_real=""
	fi
	echo "$_iface_real $_iface_fake" >$CNET_PATH/$_action
}
SRV_8021Q_change_interface_status() {
	local _iface="$1" _new_status="$2" _command
	if [ "$_new_status" = "Up" ]; then
		_command="up"
	else
		_command="down"
	fi
	ip link set $_iface $_command
}
SRV_update_managport_lowlayers() {
	local _command="$1" _bridge_obj="$2" _port_obj="$3"
	local _manag_port _manag_port_lowlayers bashism_pre bashism_post
	cmclient -v _manag_port GETO "$_bridge_obj.Port.[ManagementPort=true]"
	cmclient -v _manag_port_lowlayers GETV "$_manag_port.LowerLayers"
	[ -z "$_manag_port" ] && return
	if [ "$_command" = "add" ]; then
		case "$_manag_port_lowlayers" in
		*"$_port_obj"*) ;;

		*)
			[ -n "$_manag_port_lowlayers" ] &&
				_manag_port_lowlayers="$_manag_port_lowlayers,$_port_obj" ||
				_manag_port_lowlayers="$_port_obj"
			;;
		esac
	else
		bashism_pre=${_manag_port_lowlayers%$_port_obj,*}
		bashism_post=${_manag_port_lowlayers#*$_port_obj,}
		if [ "$_manag_port_lowlayers" = "$_port_obj" ]; then
			_manag_port_lowlayers=""
		elif [ -z "$bashism_pre" ]; then
			_manag_port_lowlayers=$bashism_post
		elif [ "$bashism_post" = "$_manag_port_lowlayers" ]; then
			_manag_port_lowlayers=${_manag_port_lowlayers%,$_port_obj*}
		else
			_manag_port_lowlayers=${_manag_port_lowlayers%$_port_obj*}${_manag_port_lowlayers#*$_port_obj,}
		fi
	fi
	cmclient -u "${AH_NAME}${obj}" SET "$_manag_port.LowerLayers" "$_manag_port_lowlayers"
}
