#!/bin/sh
service_delete_8021Q_port() {
	local _vport _vport_port _filter _filter_port objs
	this_bridge="${obj%%.Port*}" # Device.Bridging.Bridge.1
	cmclient -v objs GETO "Bridging.Filter."
	for _filter in $objs; do
		cmclient -v _filter_port GETV "$_filter.Interface"
		[ "$_filter_port" = "$obj" ] && cmclient SET "${_filter}.Status" "Error_Misconfigured"
	done
	cmclient -v tmp1 GETV "$obj.ManagementPort"
	if [ "$tmp1" = "true" ]; then
		newEnable="false"
		service_set_8021Q_Enable
	else
		cmclient -v tmp2 GETV "$this_bridge.Port.*.[ManagementPort=true].Enable"
		if [ "$tmp2" = "true" ]; then
			if [ "$bridge_standard" = "802.1Q-2005" ]; then
				SRV_8021Q_populate_bridge "rem" $this_bridge $obj "all"
			else
				SRV_8021D_populate_bridge "rem" $this_bridge $obj
			fi
		fi
		cmclient -v objs GETO "$this_bridge.VLANPort."
		for _vport in $objs; do
			cmclient -v _vport_port GETV "$_vport.Port"
			if [ "$_vport_port" = "$obj" ]; then
				cmclient SET "$_vport.Enable" "false"
				cmclient SET "$_vport.Port" ""
			fi
		done
	fi
}
service_set_8021Q_port() {
	if [ "$user" = "InterfaceStack" -a "$setEnable" = "1" ]; then
		local bridge_obj=${obj%%.Port*} bridge_enable
		[ "$newX_ADB_FakePort" = "true" ] && return
		cmclient -v bridge_enable GETV "$bridge_obj.Port.[ManagementPort=true].Enable"
		[ "$bridge_enable" != "true" ] && return
		oldStatus=$newStatus
		help_get_status_from_lowerlayers newStatus "$obj"
		if [ "$newStatus" != "$oldStatus" ]; then
			service_set_8021Q_Status
			[ "$newManagementPort" = "false" ] && cmclient SETE "$obj.Status" "$newStatus"
		fi
		return
	fi
	[ $changedLowerLayers -eq 1 ] && local_8021Q_port_update_name
	if [ $setEnable -eq 1 ]; then
		service_set_8021Q_Enable
		return
	fi
	[ $changedManagementPort -eq 1 ] && service_set_8021Q_ManagementPort
	[ $changedStatus -eq 1 ] && service_set_8021Q_Status
	if [ "$newEnable" = "true" ]; then
		[ $changedLowerLayers -eq 1 ] && service_set_8021Q_LowerLayers
		[ $changedIngressFiltering -eq 1 ] && service_set_8021Q_port_infiltering
		[ $changedPVID -eq 1 ] && service_set_8021Q_port_pvid
	fi
}
service_set_8021Q_Enable() {
	local _port_obj _command _status_new _lowlayer_status
	local_8021Q_port_prepare_bridge
	if [ "$newManagementPort" = "true" ]; then
		if [ "$newEnable" = "true" ]; then
			SRV_8021Q_create_vlanbridge "add" "$br_name" "$bridge_type" "0"
			if [ "$bridge_standard" = "802.1Q-2005" ]; then
				SRV_8021Q_populate_bridge "add" $this_bridge "all" "all"
			else
				SRV_8021D_populate_bridge "add" $this_bridge "all"
				[ "$user" != "init" ] && local_8021D_enable_filters "add" "$this_bridge"
			fi
			local_8021Q_port_update_status "Dormant" "Up"
			_status_new="Up"
		else
			if [ "$user" != "boot" ]; then
				if [ "$bridge_standard" = "802.1Q-2005" ]; then
					SRV_8021Q_populate_bridge "rem" $this_bridge "all" "all"
				else
					local_8021D_enable_filters "rem" "$this_bridge"
					SRV_8021D_populate_bridge "rem" $this_bridge "all"
				fi
				SRV_8021Q_create_vlanbridge "rem" "$br_name" "$bridge_type" "0"
			fi
			local_8021Q_port_update_status "Up" "Dormant"
			_status_new="Down"
		fi
	else
		help_get_status_from_lowerlayers _status_new "$obj" "$newEnable" "$newLowerLayers"
		cmclient -v tmp GETV "$this_bridge.Port.*.[ManagementPort=true].Enable"
		if [ "$tmp" = "true" ]; then
			_port_obj="$obj"
			[ "$newEnable" = "true" ] && _command="add" || _command="rem"
			if [ "$bridge_standard" = "802.1Q-2005" ]; then
				SRV_8021Q_populate_bridge $_command $this_bridge $_port_obj "all"
			else
				SRV_8021D_populate_bridge $_command $this_bridge $_port_obj
			fi
		else
			[ "$_status_new" = "Up" ] && _status_new="Dormant" # Waiting for the Bridge
		fi
	fi
	[ "$newManagementPort" = "true" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "$_status_new" ||
		cmclient SETE "$obj.Status" "$_status_new"
}
service_set_8021Q_ManagementPort() {
	local _port_obj
	local_8021Q_port_prepare_bridge
	if [ "$newManagementPort" = "true" ]; then
		echo "### $_AH_NAME: SET <$obj.Name> <$br_name> ###"
		cmclient SETE "$obj.Name" "$br_name"
		local pobj
		cmclient -v pobj GETO "$this_bridge.Port.[ManagementPort=false]"
		for _port_obj in $pobj; do
			newLowerLayers=""$newLowerLayers","$_port_obj""
		done
		newLowerLayers=${newLowerLayers#,} # Remove trailing ','
		cmclient -u "${AH_NAME}${obj}" SET "$obj.LowerLayers" "$newLowerLayers"
		if [ "$newEnable" = "true" ]; then
			SRV_8021Q_create_vlanbridge "add" "$br_name" "$bridge_type" "0"
			if [ "$bridge_standard" = "802.1Q-2005" ]; then
				SRV_8021Q_populate_bridge "add" "$this_bridge" "all" "all"
			else # 802.1D-2004
				SRV_8021D_populate_bridge "add" "$this_bridge" "all"
			fi
		fi
	else
		[ "$newEnable" = "true" ] && cmclient SET "$obj.Enable" "false"
		cmclient -u "${AH_NAME}${obj}" SET "$obj.LowerLayers" ""
		cmclient SETE "$obj.Name" ""
	fi
}
service_set_8021Q_Status() {
	local _interface
	if [ -n "$newLowerLayers" ] && [ "$newManagementPort" = "false" ] && [ "$newStatus" = "Up" ]; then
		help_lowlayer_ifname_get _interface "$newLowerLayers"
		help_if_link_change "$_interface" "$newStatus" "$AH_NAME"
	fi
}
service_set_8021Q_LowerLayers() {
	local _managport_obj
	if [ "$newManagementPort" = "true" ]; then
		return
	fi
	local_8021Q_port_prepare_bridge
	cmclient -v _managport_obj GETO "$this_bridge.Port.*.[ManagementPort=true]"
	cmclient -v tmp GETV "$_managport_obj.Enable"
	if [ "$tmp" = "true" ]; then
		if [ "$bridge_standard" = "802.1Q-2005" ]; then
			SRV_8021Q_populate_bridge "rem" "$this_bridge" "$obj" "all" "LowerLayers" "$oldLowerLayers"
			SRV_8021Q_populate_bridge "add" "$this_bridge" "$obj" "all"
		else # 802.1D-2004
			SRV_8021D_populate_bridge "rem" "$this_bridge" "$obj" "LowerLayers" "$oldLowerLayers"
			SRV_8021D_populate_bridge "add" "$this_bridge" "$obj"
		fi
	fi
}
service_set_8021Q_port_infiltering() {
	local _managport_obj _infiltering_old _vlan_obj _vlan_id
	local_8021Q_port_prepare_bridge
	if [ "$newManagementPort" = "true" ] && [ "$newEnable" = true ]; then
		cmclient -v _vlan_obj GETO "$this_bridge.VLAN.[VLANID=$newPVID]"
		if [ -n "$_vlan_obj" ]; then
			if [ "$newIngressFiltering" = "true" ]; then
				SRV_8021Q_populate_bridge "rem" "$this_bridge" "all" "$_vlan_obj" "ManagementPortPVID" "0"
			else
				_vlan_id="$newPVID"
				SRV_8021Q_populate_bridge "rem" "$this_bridge" "all" "$_vlan_obj" "ManagementPortPVID" "$_vlan_id"
			fi
			SRV_8021Q_populate_bridge "add" "$this_bridge" "all" "$_vlan_obj"
		fi ############################
	else
		if [ "$bridge_standard" = "802.1Q-2005" ]; then
			cmclient -v _managport_obj GETO "$this_bridge.Port.*.[ManagementPort=true]"
			if [ "$newIngressFiltering" = "true" ]; then
				_infiltering_old="false"
			else
				_infiltering_old="true"
			fi
			cmclient -v tmp GETV "$_managport_obj.Enable"
			if [ "$tmp" = "true" ]; then
				SRV_8021Q_populate_bridge "rem" "$this_bridge" "$obj" "all" "IngressFiltering" "$_infiltering_old"
				SRV_8021Q_populate_bridge "add" "$this_bridge" "$obj" "all"
			fi
		fi
	fi
}
service_set_8021Q_port_pvid() {
	local _vlan_obj
	local_8021Q_port_prepare_bridge
	if [ "$newManagementPort" = "true" ]; then
		if [ "$newIngressFiltering" = "true" ] && [ "$newEnable" = "true" ]; then
			cmclient -v _vlan_obj GETO "$this_bridge.VLAN.[VLANID=$oldPVID]"
			if [ -n "$_vlan_obj" ]; then
				SRV_8021Q_populate_bridge "rem" "$this_bridge" "all" "$_vlan_obj" "ManagementPortPVID" "$oldPVID"
				SRV_8021Q_populate_bridge "add" "$this_bridge" "all" "$_vlan_obj"
			fi
			cmclient -v _vlan_obj GETO "$this_bridge.VLAN.[VLANID=$newPVID]"
			if [ -n "$_vlan_obj" ]; then
				SRV_8021Q_populate_bridge "rem" "$this_bridge" "all" "$_vlan_obj" "ManagementPortPVID" "0"
				SRV_8021Q_populate_bridge "add" "$this_bridge" "all" "$_vlan_obj"
			fi
		fi
	fi
}
local_8021Q_port_prepare_bridge() {
	this_bridge="${obj%.Port*}"
	bridge_number=$((${this_bridge##*Bridge.} - 1))
	cmclient -v bridge_standard GETV "$this_bridge.Standard"
	cmclient -v bridge_type GETV "$this_bridge.X_ADB_BridgeType"
	br_name="$BRIDGE_PREFIX""$bridge_number"
}
local_8021Q_port_update_status() {
	local _current_status="$1" _new_status="$2" _port_obj _port_status pobj
	cmclient -v pobj GETO "$this_bridge.Port.[ManagementPort=false]"
	for _port_obj in $pobj; do
		cmclient -v _port_status GETV "$_port_obj.Status"
		if [ "$_port_status" = "$_current_status" ]; then
			cmclient SETE "$_port_obj.Status" "$_new_status"
		fi
	done
}
local_8021Q_port_update_name() {
	local _interface_name
	[ "$newManagementPort" = "true" ] && return
	help_lowlayer_ifname_get "_interface_name" "$newLowerLayers"
	cmclient SETE "$obj.Name" "$_interface_name"
}
local_8021D_enable_filters() {
	local _this_bridge="$2" _command="$1" _filter_obj _status="Disabled" bobj
	[ "$_command" = "add" ] && _status="Enabled"
	cmclient -v bobj GETO "Bridging.Filter.*.[Bridge=${_this_bridge}]"
	for _filter_obj in $bobj; do
		cmclient SET "${_filter_obj}.Status" "$_status"
	done
}
