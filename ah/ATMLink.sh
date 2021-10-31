#!/bin/sh
AH_NAME="ATMLink"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_status.sh
. /etc/ah/IPv6_helper_functions.sh
. /etc/ah/helper_stats.sh
. /etc/ah/target.sh
ifname=$newName
xtm_aal=
xtm_addr=
xtm_encap=
xtm_mq=
xtm_linktype=
xtm_portId=
xtm_reconf() {
	help_check_cwmp_progress
	service_get_vars
	service_read_add_qos "false"
	help_xtm_link_down "$newName"
	if [ "$newEnable" = "false" ]; then
		xtm_config_conn_netdev "delete" "$newName" "$oldDestinationAddress"
		xtm_config_conn_add "delete" "$oldDestinationAddress"
	else
		service_reconf "$obj" "$newStatus" "false" "$newName" "$newLowerLayers" "$oldDestinationAddress" "" "$newX_ADB_MTU"
		sleep 1
		xtm_config_conn_netdev "delete" "$ifname" "$oldDestinationAddress"
		xtm_config_conn_add "delete" "$oldDestinationAddress"
		service_reconf "$obj" "$newStatus" "true" "$newName" "$newLowerLayers" "$newDestinationAddress" "1" "$newX_ADB_MTU"
	fi
	exit 0
}
xtm_config_conn_state() {
	local xtm_vpi=${2%%/*} xtm_vci=${2##*/}
	xtm_connection_state "$xtm_portId.$xtm_vpi.$xtm_vci" "$1"
}
xtm_config_atm_probe() {
	local doamping vc_list _vc_list vpi vci addr found=0
	cmclient -v doamping GETV "${_path}.X_ADB_DisableOAMPing"
	cmclient -v vc_list GETV "${_path}.VCSearchList"
	[ -z "$vc_list" -a "$doamping" = "true" -a ! -x /etc/ah/DslBonding.sh ] && pvc="${2}" && return 0
	IFS=" ,"
	case ",${vc_list}," in
	*",$2,"* | *" $2 "*)
		for vc in $vc_list; do
			[ "$vc" = "$2" ] && continue
			_vc_list="${_vc_list:+$_vc_list,}${vc}"
		done
		;;
	esac
	_vc_list="${2},${_vc_list:-$vc_list}"
	for vc in ${_vc_list}; do
		[ -z "$vc" ] && continue
		vpi=${vc%%/*}
		vci=${vc##*/}
		addr="$xtm_portId.$vpi.$vci"
		xtm_add_connection "$addr" "$xtm_aal" "$xtm_linktype" "$xtm_encap" "$xtm_tdte_index"
		xtm_add_queue "$addr" 10 0 rr 1
		xtm_create_network_device "$addr" "atmprobe0"
		ifconfig atmprobe0 up
		sleep 3
		xtm_send_oam "$addr" "f5end" && found=1
		xtm_delete_network_device "$addr"
		xtm_delete_queue "$addr" 0
		xtm_delete_connection "$addr"
		if [ $found -eq 1 ]; then
			pvc="${vc}"
			if [ "$_vc_list" != "$vc_list" -o "$pvc" != "$2" ]; then
				[ "$pvc" != "$2" ] && cmclient -u "${AH_NAME}${1}" SET "${1}.DestinationAddress" "${pvc}"
				[ "$_vc_list" != "$vc_list" ] && cmclient -u "${AH_NAME}${1}" SET "${1}.VCSearchList" "$_vc_list"
				cmclient SAVE
			fi
			unset IFS
			return 0
		fi
	done
	[ -x /etc/ah/DslBonding.sh -a "$doamping" = "true" ] && pvc="${2}" && return 0
	cmclient -u "${AH_NAME}${1}" SET "${1}.Status" "Error"
	return 1
}
xtm_config_conn_add() {
	local baseSubPrio=0
	if [ "$1" = "add" ]; then
		xtm_config_atm_probe "$_path" "$2" || return 1
		local xtm_vpi=${pvc%%/*}
		local xtm_vci=${pvc##*/}
		xtm_add_connection "$xtm_portId.$xtm_vpi.$xtm_vci" "$xtm_aal" "$xtm_linktype" "$xtm_encap" "$xtm_tdte_index"
	else
		local xtm_vpi=${2%%/*}
		local xtm_vci=${2##*/}
		xtm_delete_queue "$xtm_portId.$xtm_vpi.$xtm_vci" "$baseSubPrio"
		xtm_delete_connection "$xtm_portId.$xtm_vpi.$xtm_vci"
	fi
	if [ "$1" = "add" ]; then
		xtm_add_queue $xtm_portId.$xtm_vpi.$xtm_vci 400 $baseSubPrio rr 10
	fi
	:
}
xtm_config_conn_do_add() {
	local cmd="$1" path="$3"
	if [ -n "$xtm_qos_class" ]; then
		tdte_params=$(xtm_get_tdte_params "$path")
		xtm_tdte_index=$(xtm_get_tdte_index $tdte_params)
	else
		xtm_tdte_index="1"
	fi
	xtm_config_conn_add "$cmd" "$2"
}
xtm_config_conn_netdev() {
	local _ifname="$2" xtm_vpi=${3%%/*} xtm_vci=${3##*/} _path="$4" _mac="" _mtu="$5"
	[ -z "$_mtu" ] && _mtu=0
	if [ "$1" = "create" ]; then
		. /etc/ah/helper_dsl.sh
		_mac=$(help_get_atm_mac_address ${_path})
		xtm_create_network_device "$xtm_portId.$xtm_vpi.$xtm_vci" "$_ifname"
	else
		tc qdisc del dev "$_ifname" root fbd
		xtm_delete_network_device "$xtm_portId.$xtm_vpi.$xtm_vci"
	fi
	if [ "$1" = "create" ]; then
		ifconfig "$_ifname" hw ether "$_mac"
		help_serialize_unlock "get_mac_lock"
		[ $_mtu -gt 0 ] && ip link set "$_ifname" mtu "$_mtu"
		tc qdisc add dev "$_ifname" root fbd
	fi
}
xtm_get_tdte_index() {
	arg_pcr=${2:-"0"} arg_scr=${3:-"0"} arg_mbs=${4:-"0"} arg_mcr=${5:-"0"}
	xtm_show_traffic_desc_table | while IFS=" " read t_index t_type t_pcr t_scr t_mbs t_mcr _; do
		if [ "$t_type" = "$1" ]; then
			if [ "$t_pcr" = "$arg_pcr" -a "$t_scr" = "$arg_scr" -a "$t_mbs" = "$arg_mbs" -a "$t_mcr" = "$arg_mcr" ]; then
				echo -n "$t_index"
				return 0
			fi
		fi
	done
	return 1
}
xtm_get_aal() {
	case "$xtm_aal" in
	"AAL1" | "AAL2" | "AAL3" | "AAL4")
		echo "unsupported"
		;;
	"AAL5")
		echo "aal5"
		;;
	*)
		echo ""
		;;
	esac
}
xtm_get_encaps() {
	local _link="$1" _encap="$2"
	if [ "$_encap" = "LLC" ]; then
		case "$_link" in
		"EoA")
			echo "llcsnap_eth"
			;;
		"IPoA")
			echo "llcsnap_rtip"
			;;
		"PPPoA")
			echo "llcencaps_ppp"
			;;
		"CIP")
			echo ""
			;;
		*) ;;

		esac
	elif [ "$_encap" = "VCMUX" ]; then
		case "$_link" in
		"EoA")
			echo "vcmux_eth"
			;;
		"IPoA")
			echo "vcmux_ipoa"
			;;
		"PPPoA")
			echo "vcmux_pppoa"
			;;
		"CIP")
			echo ""
			;;
		*) ;;

		esac
	fi
	echo ""
}
xtm_get_qos() {
	local _qos="$1"
	case $_qos in
	"UBR")
		echo "ubr"
		;;
	"CBR")
		echo "cbr"
		;;
	"VBR-nrt")
		echo "nrtvbr"
		;;
	"VBR-rt")
		echo "rtvbr"
		;;
	"GFR")
		echo ""
		;;
	"UBR+")
		echo "ubr_pcr"
		;;
	"ABR")
		echo "ubr_pcr"
		;;
	*) ;;

	esac
}
check_enc() {
	local _path=$1 _chan=$2 _ifname=$3 _addr=$4 objs
	case "$_chan" in
	Device.DSL.BondingGroup.*)
		cmclient -v _chan GETV "$_chan.LowerLayers"
		;;
	esac
	set -f
	IFS=','
	set -- $_chan
	unset IFS
	set +f
	for _chan; do
		cmclient -v objs GETV "$_chan.LinkEncapsulationUsed"
		case "$objs" in
		*"PTM")
			exit 0
			;;
		esac
	done
}
service_align_upper_layers() {
	local _path="$1" _enable="$2" eth_link=""
	align_upper_layers "$_path" "$_enable" "Device.Bridging.Bridge.*.Port"
	cmclient -v eth_link GETO "Device.Ethernet.Link.[LowerLayers=$_path]"
	if [ -n "$eth_link" ]; then
		align_upper_layers "$eth_link" "$_enable" "Device.Ethernet.VLANTermination"
	fi
}
service_do_reconf() {
	local _path="$1" _status="$2" _ifname="$3" _enable="$4" _addr="$5" _mtu="$6"
	local itf itf_list
	if [ "$changedEnable" = "1" -o "$changedDestinationAddress" = "1" ]; then
		if [ "$_enable" = "false" ]; then
			xtm_config_conn_state "disable" "$_addr"
		elif [ "$_enable" = "true" ]; then
			xtm_config_conn_state "enable" "$_addr"
		fi
	fi
	xtm_qos_class=$(service_read_add_qos "$_enable" "$_path")
	if [ "$_enable" = "true" -a "$_status" = "Up" ]; then
		for ptmdev in /sys/class/net/ptm*; do
			[ -d "$ptmdev" ] || continue
			echo "### $AH_NAME: Executing <ip link set ${ptmdev##*/} down>"
			xdsl_set_link "${ptmdev##*/}" down
		done
		if ! [ -d "/sys/class/net/$_ifname" ]; then
			xtm_config_conn_do_add "add" "$_addr" "$_path" || return 1
			xtm_config_conn_state "enable" "$pvc"
			xtm_config_conn_netdev "create" "$_ifname" "$pvc" "$_path" "$_mtu"
			xtm_created=1
			help_ipv6_reconf_iface "$_ifname"
		fi
	fi
	:
}
service_status_reconf() {
	local _path="$1" _status="$2" _enable="$3" _ifname="$4" _lowlayer_status="$5"
	local _addr="$6" _mtu="$7"
	xtm_created=0
	[ "$_lowlayer_status" = "Up" -a "$_enable" = "true" ] &&
		check_enc "$_path" "$obj" "$_ifname" "$_addr"
	help_get_status_from_lowerlayers new_status "$_path" "$_enable" "$_lowlayer_status" true
	service_do_reconf "$_path" "$new_status" "$_ifname" "$_enable" "$_addr" "$_mtu" || return 1
	[ "$_enable" = "true" -a "$xtm_created" -eq 1 ] &&
		service_align_upper_layers "$_path" "$_enable"
	if [ "$new_status" = "Up" ]; then
		xdsl_set_link "$_ifname" up
	elif [ "$new_status" = "LowerLayerDown" ]; then
		xdsl_set_link "$_ifname" down
		if [ -x /etc/ah/DslBonding.sh ]; then
			xtm_config_conn_netdev "delete" "$_ifname" "$_addr"
			xtm_config_conn_add "delete" "$_addr"
		fi
	fi
	cmclient SET -u "${AH_NAME}${_path}" "$_path.Status" "$new_status"
}
service_reconf() {
	local _path="$1" _status="$2" _enable="$3" _ifname="$4" _lowlayer="$5"
	local _addr="$6" _force_status="$7" _mtu="$8" new_status
	help_get_status_from_lowerlayers new_status "$_path" "$_enable" "$_lowLayer"
	[ "$_enable" = "false" ] &&
		service_align_upper_layers "$_path" "$_enable"
	service_do_reconf "$_path" "$new_status" "$_ifname" "$_enable" "$_addr" "$_mtu"
	[ "$_enable" = "true" ] &&
		service_align_upper_layers "$_path" "$_enable"
	if [ "$new_status" != "$_status" -o -n "$_force_status" ]; then
		[ "$new_status" = "Up" ] && xdsl_set_link "$_ifname" up
		cmclient SET -u "${AH_NAME}${_path}" "$_path.Status" "$new_status"
	fi
}
xtm_get_tdte_params() {
	local _obj=${1:-$obj} val
	case "$_obj" in
	*.QoS) ;;

	*)
		_obj=$_obj.QoS
		;;
	esac
	_obj=${1:-${obj%.*}}.QoS
	cmclient -v val GETV $_obj.QoSClass
	local qos_class=${newQoSClass-$val}
	local qos=$(xtm_get_qos $qos_class) pcr="" mbs="" scr="" mcr=""
	if [ -n "$qos" ]; then
		case "$qos_class" in
		"UBR") ;;

		"CBR")
			cmclient -v val GETV $_obj.PeakCellRate
			pcr=${newPeakCellRate-$val}
			: ${pcr:=0}
			;;
		"VBR-nrt" | "VBR-rt")
			cmclient -v val GETV $_obj.PeakCellRate
			pcr=${newPeakCellRate-$val}
			cmclient -v val GETV $_obj.MaximumBurstSize
			mbs=${newMaximumBurstSize-$val}
			cmclient -v val GETV $_obj.SustainableCellRate
			scr=${newSustainableCellRate-$val}
			: ${pcr:=0} ${mbs:=0} ${scr:=0}
			;;
		"UBR+")
			cmclient -v val GETV $_obj.PeakCellRate
			pcr=${newPeakCellRate-$val}
			[ -z "$pcr" ] && qos="ubr"
			;;
		"ABR")
			cmclient -v val GETV $_obj.PeakCellRate
			pcr=${newPeakCellRate-$val}
			if [ -n "$pcr" ]; then
				cmclient -v val GETV $_obj.X_ADB_ATMMinimumCellRate
				mcr=${newX_ADB_ATMMinimumCellRate-$val}
			fi
			if [ -z "$pcr" -o -z "$mcr" ]; then
				qos="ubr" mcr="" pcr=""
			fi
			;;
		esac
	fi
	echo "$qos $pcr $scr $mbs $mcr"
}
service_read_add_qos() {
	local enable="$1"
	local qosobj=${2:-$obj}
	[ -z "$enable" ] && exit
	tdte_params=$(xtm_get_tdte_params "$qosobj")
	local qos=${tdte_params%%" "*}
	if [ -n "$qos" ]; then
		if [ "$enable" = "true" ]; then
			[ -n "$(xtm_get_tdte_index $tdte_params)" ] && echo "$qos" && return
			xtm_add_tdte $tdte_params >/dev/null 2>&1
		else
			xtm_tdte_index=$(xtm_get_tdte_index $tdte_params)
			xtm_delete_tdte $xtm_tdte_index >/dev/null 2>&1
		fi
		echo "$qos"
	fi
}
service_get() {
	local object="$1" param="$2" buf=""
	case "$object" in
	*"Stats")
		object="${object%%.Stats}"
		;;
	esac
	case "$param" in
	LastChange)
		. /etc/ah/helper_lastChange.sh
		help_lastChange_get "$object"
		;;
	*)
		local currentVal parVal
		cmclient -v ifname GETV "$object.Name"
		if [ -n "$ifname" ]; then
			help_get_base_stats_core "$obj.$param" "$ifname" currentVal
			eval "parVal=\$new$2"
			if [ ${parVal:=0} -le $currentVal ]; then
				echo $((currentVal - parVal))
			else
				echo $(((1 << 32) - (parVal - currentVal)))
			fi
		else
			echo ""
		fi
		;;
	esac
}
service_get_vars() {
	local x lpath
	set -f
	IFS=','
	if [ -n "$1" ]; then
		case "$2" in
		Device.DSL.BondingGroup.*)
			cmclient -v x GETV $2.LowerLayers
			for x in $x; do
				cmclient -v lpath GETV $x.LPATH
				lpath=$((lpath + 1))
				if [ "${xtm_portId:-$lpath}" != "$lpath" ]; then
					cmclient SET -u "${AH_NAME}${1}" "$1.Status" "Error"
					exit 0
				fi
				xtm_portId=$lpath
			done
			;;
		*)
			cmclient -v xtm_portId GETV "$2.LPATH"
			xtm_portId=$((xtm_portId + 1))
			;;
		esac
		cmclient -v xtm_aal GETV "$1.AAL"
		cmclient -v xtm_encap GETV "$1.Encapsulation"
		cmclient -v xtm_mq GETV "$1.X_ADB_MultiQueue"
		cmclient -v xtm_linktype GETV "$1.LinkType"
		cmclient -v xtm_addr GETV "$1.DestinationAddress"
	else
		case "$newLowerLayers" in
		Device.DSL.BondingGroup.*)
			cmclient -v x GETV $newLowerLayers.LowerLayers
			for x in $x; do
				cmclient -v lpath GETV $x.LPATH
				lpath=$((lpath + 1))
				if [ "${xtm_portId:-$lpath}" != "$lpath" ]; then
					cmclient SET -u "${AH_NAME}${obj}" "$obj.Status" "Error"
					exit 0
				fi
				: ${xtm_portId:=$lpath}
			done
			;;
		*)
			cmclient -v xtm_portId GETV "$2.LPATH"
			xtm_portId=$((xtm_portId + 1))
			;;
		esac
		: ${xtm_aal:=$newAAL}
		: ${xtm_encap:=$newEncapsulation}
		: ${xtm_linktype:=$newLinkType}
	fi
	unset IFS
	set +f
	[ $xtm_portId -gt 1 ] && xtm_portId=1
}
service_config() {
	local _name _tmp
	case "$obj" in
	Device.ATM.Link.*.QoS.*)
		service_read_add_qos
		;;
	Device.ATM.Link.*)
		if [ "$setX_ADB_Reset" = "1" ]; then
			cmclient -v _name GETV "${obj%.Stats}.Name"
			help_reset_stats $obj
		fi
		if [ "$changedStatus" = "1" ]; then
			return 0
		fi
		if [ "$changedEnable" = "1" ]; then
			service_get_vars
			if [ "$newEnable" = "false" ]; then
				help_if_link_change "$newName" "Down" "$AH_NAME"
			else
				check_enc "$obj" "$newLowerLayers" "$newName" "$newDestinationAddress"
			fi
			service_reconf "$obj" "$newStatus" "$newEnable" "$newName" "$newLowerLayers" "$newDestinationAddress" "" "$newX_ADB_MTU"
		fi
		if [ "$changedDestinationAddress" = "1" -a -n "$oldDestinationAddress" ] ||
			[ "$changedEncapsulation" = "1" -a -n "$oldEncapsulation" ]; then
			xtm_reconf &
		fi
		;;
	*)
		local status_val enable_val currlayer_ifname mtu
		cmclient -v _tmp GETO "Device.ATM.Link.*.[LowerLayers=$obj]"
		for lower_layers in $_tmp; do
			cmclient -v status_val GETV "$lower_layers.Status"
			cmclient -v enable_val GETV "$lower_layers.Enable"
			cmclient -v currlayer_ifname GETV "$lower_layers.Name"
			cmclient -v mtu GETV "$lower_layers.X_ADB_MTU"
			service_get_vars "$lower_layers" "$obj"
			service_status_reconf "$lower_layers" "$status_val" "$enable_val" "$currlayer_ifname" "$newStatus" "$xtm_addr" "$mtu"
		done
		;;
	esac
}
service_delete() {
	[ -z "$oldDestinationAddress" -o -z "$oldEncapsulation" -o -z "$oldLinkType" ] && return
	service_get_vars
	service_read_add_qos "false"
	help_xtm_link_down "$oldName"
	xtm_config_conn_netdev "delete" "$oldName" "$oldDestinationAddress"
	xtm_config_conn_state "disable" "$oldDestinationAddress"
	xtm_config_conn_add "delete" "$oldDestinationAddress"
}
delete_netdevs() {
	local obj objs chan=$1 _name
	cmclient -v objs GETO "Device.ATM.Link.*.[LowerLayers=$chan]"
	for obj in $objs; do
		service_get_vars $obj
		service_read_add_qos "false"
		cmclient -v _name GETV "$obj.Name"
		cmclient SETE "$obj".Status Error
		help_xtm_link_down "$_name"
		xtm_config_conn_netdev "delete" "$_name" $xtm_addr
		xtm_config_conn_state "disable" $xtm_addr
		xtm_config_conn_add "delete" $xtm_addr
	done
	exit 0
}
[ $# -eq 2 -a "$1" = "del" ] && delete_netdevs $2
case "$op" in
d)
	service_delete
	;;
g)
	for arg; do # Arg list as separate words
		service_get "$obj" "$arg"
	done
	;;
s)
	service_config
	;;
esac
exit
