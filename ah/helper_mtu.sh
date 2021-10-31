#!/bin/sh
. /etc/ah/helper_ifname.sh
get_vlan_default_mtu() {
	local output_variable=$1 vlan_obj=$2 vlan_lower_layer lower_layer_mtu=1500
	local vlan_mtu upstream
	help_active_lowlayer vlan_lower_layer $vlan_obj
	help_active_lowlayer vlan_lower_layer $vlan_lower_layer
	case $vlan_lower_layer in
	"Device.ATM.Link"*)
		cmclient -v lower_layer_mtu GETV ${vlan_lower_layer}.X_ADB_MTU
		[ "$lower_layer_mtu" = "0" ] && lower_layer_mtu=9180
		;;
	"Device.PTM.Link"*)
		cmclient -v lower_layer_mtu GETV ${vlan_lower_layer}.X_ADB_MTU
		[ "$lower_layer_mtu" = "0" ] && lower_layer_mtu=1500
		;;
	"Device.Ethernet.Interface"*)
		cmclient -v upstream GETV ${vlan_lower_layer}.Upstream
		[ "${upstream}" = "true" ] && cmclient -v lower_layer_mtu GETV Device.Ethernet.X_ADB_MaxSupportedMTUSize
		;;
	esac
	vlan_mtu=$((lower_layer_mtu - 4))
	eval $output_variable='$vlan_mtu'
}
help_get_default_mtu() {
	[ "$1" != "__o" ] && local __o
	[ "$1" != "__r" ] && local __r
	local current_vlan_mtu current_ll bridge_port_lower_layers upstream
	case "$2" in
	"Device.X_ADB_VPN.GRETap"*)
		__r=1462
		;;
	"Device.ATM.Link"*)
		__r=9180
		;;
	"Device.PPP.Interface"*)
		help_active_lowlayer __o $2
		if [ "${__o%.*}" = Device.Ethernet.VLANTermination ]; then
			get_vlan_default_mtu __r $__o
		else
			__r=1500
		fi
		__r=$((__r - 8))
		;;
	"Device.Ethernet.VLANTermination"*)
		get_vlan_default_mtu __r $2
		;;
	"Device.Bridging.Bridge"*)
		__r=1500
		cmclient -v bridge_port_lower_layers GETV "$2".LowerLayers
		for bridge_port_lower_layers in $bridge_port_lower_layers; do
			while [ -n "$bridge_port_lower_layers" ]; do
				current_ll=${bridge_port_lower_layers%%,*}
				bridge_port_lower_layers=${bridge_port_lower_layers#*,}
				[ "$current_ll" = "$bridge_port_lower_layers" ] && bridge_port_lower_layers=""
				case $current_ll in
				"Device.Ethernet.VLANTermination"*)
					get_vlan_default_mtu current_vlan_mtu $current_ll
					[ $current_vlan_mtu -lt $__r ] && __r=$current_vlan_mtu
					;;
				esac
			done
		done
		;;
	"Device.Ethernet.Interface"*)
		__r=1500
		cmclient -v upstream GETV $2.Upstream
		[ "${upstream}" = "true" ] && cmclient -v __r GETV Device.Ethernet.X_ADB_MaxSupportedMTUSize
		;;
	"Device.Ethernet.Link"*)
		__r=1500
		help_active_lowlayer current_ll $2
		if [ "${current_ll%.*}" = "Device.Ethernet.Interface" ]; then
			cmclient -v upstream GETV ${current_ll}.Upstream
			[ "${upstream}" = "true" ] && cmclient -v __r GETV Device.Ethernet.X_ADB_MaxSupportedMTUSize
		elif [ "${current_ll%.*}" = "Device.PTM.Link" ]; then
			cmclient -v __r GETV ${current_ll}.X_ADB_MTU
			[ "${__r}" = "0" -o "${__r}" = "" ] && __r=1500
		fi
		;;
	*)
		__r=1500
		;;
	esac
	eval $1='$__r'
}
help_set_mtu() {
	local _lowlayer="$1" _upperlayer="$2" MaxMTUSize="MaxMTUSize" _obj=$obj
	case "$obj" in
	*"Bridging"*)
		setMaxMTUSize="$setX_ADB_MaxMTUSize"
		changedMaxMTUSize="$changedX_ADB_MaxMTUSize"
		newMaxMTUSize="$newX_ADB_MaxMTUSize"
		MaxMTUSize="X_ADB_MaxMTUSize"
		_obj=${obj%%.Port*}
		;;
	esac
	if [ $setMaxMTUSize -eq 1 ]; then
		cmclient SETE $_obj.X_ADB_AutoMTU false
		[ "$newX_ADB_AutoMTU" = "true" ] && changedX_ADB_AutoMTU=1
		newX_ADB_AutoMTU=false
	fi
	[ "$user" = "boot" -o $changedMaxMTUSize -eq 1 -o $changedX_ADB_AutoMTU -eq 1 -o $changedEnable -eq 1 ] || return
	if [ "$newX_ADB_AutoMTU" = "true" ]; then
		help_get_default_mtu newMaxMTUSize "$_lowlayer"
		cmclient SETE $_obj.$MaxMTUSize "$newMaxMTUSize"
	fi
	if [ "${_lowlayer%.*}" = "Device.PPP.Interface" ]; then
		[ $changedMaxMTUSize -eq 1 ] && cmclient SET "$_lowlayer.Reset true"
	else
		help_lowlayer_set_mtu "$_upperlayer" "$newMaxMTUSize"
		[ -n "$lowlayer_ifname" ] && ip link set "$lowlayer_ifname" mtu "$newMaxMTUSize"
	fi
}
help_lowlayer_set_mtu() {
	local ul=$1 if_mtu=$2 cmd="true" ll="" llnm lltag old_mtu mulit_ll=""
	while :; do
		multi_ll=${multi_ll#$ll}
		[ -n "$multi_ll" ] && multi_ll=${multi_ll#,} || cmclient -v multi_ll GETV "$ul.X_ADB_ActiveLowerLayer"
		[ ${#multi_ll} -eq 0 ] && cmclient -v multi_ll GETV "$ul.LowerLayers"
		ll=$multi_ll
		[ ${#ll} -eq 0 ] && break || ll=${ll%%,*}
		cmclient -v llnm GETV "$ll.Name"
		if [ ${#llnm} -eq 0 -a "${ll%.*}" = "Device.Ethernet.VLANTermination" ]; then
			cmclient -v llnm GETV "$ll.X_ADB_ActiveLowerLayer"
			[ ${#llnm} -eq 0 ] && cmclient -v llnm GETV "$ll.LowerLayers"
			llnm=${llnm%%,*}
			cmclient -v llnm GETV "$llnm.Name"
			if [ ${#llnm} -gt 0 ]; then
				cmclient -v lltag GETV "$ll.VLANID"
				llnm="$llnm.$lltag"
			fi
		fi
		[ ${#llnm} -eq 0 ] && break
		[ -f /sys/class/net/$llnm/mtu ] || break
		read old_mtu </sys/class/net/$llnm/mtu
		case $ul in
		Device.PPP.Interface.*)
			if_mtu=$((if_mtu + 8))
			;;
		Device.Ethernet.VLANTermination.*)
			if_mtu=$((if_mtu + 4))
			;;
		Device.Bridging.Bridge.*)
			[ ${old_mtu:-65536} -ne $if_mtu ] && cmd="ip link set $llnm mtu $if_mtu && $cmd"
			ul=$ll
			continue
			;;
		Device.Ethernet.Link.*)
			ul=$ll
			continue
			;;
		*)
			break
			;;
		esac
		[ ${old_mtu:-65536} -lt $if_mtu ] && cmd="ip link set $llnm mtu $if_mtu && $cmd"
		ul=$ll
	done
	[ "$cmd" != "true" ] && eval $cmd
}
