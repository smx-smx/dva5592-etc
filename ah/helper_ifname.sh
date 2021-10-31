#!/bin/sh
help_active_lowlayer() {
	[ "$1" != "__ll" ] && local __ll
	cmclient -v __ll GETV "$2.X_ADB_ActiveLowerLayer"
	[ ${#__ll} -eq 0 ] && cmclient -v __ll GETV -u "$3" "$2.LowerLayers"
	__ll=${__ll%%,*}
	eval $1='$__ll'
}
help_lowlayer_ifname_get() {
	[ "$1" != "lowlayer" ] && local lowlayer
	[ "$1" != "ifname" ] && local ifname
	[ "$1" != "vlan" ] && local vlan
	[ "$1" != "suffix" ] && local suffix=""
	[ "$1" != "bridge_num" ] && local bridge_num=""
	[ "$1" != "bridge_obj" ] && local bridge_obj=""
	lowlayer=$3
	[ ${#lowlayer} -eq 0 ] && lowlayer=${2%%,*}
	while [ ${#lowlayer} -gt 0 ]; do
		if [ "${lowlayer##*X_ADB_VXLAN.Tunnel*}" != "${lowlayer}" ]; then
			cmclient -v bridge_obj GETO Device.Bridging.Bridge.Port.[LowerLayers,${lowlayer}]
			bridge_num=${bridge_obj##Device.Bridging.Bridge.}
			bridge_num=${bridge_num%%.Port.*}
			ifname="vxlan$bridge_num"
			break
		fi
		cmclient -v ifname -u "$4" GETV "$lowlayer.Name"
		if [ ${#ifname} -eq 0 ]; then
			cmclient -v lowlayer -u "$4" GETO "$lowlayer"
			[ ${#lowlayer} -eq 0 ] && break
		fi
		case $ifname in
		ppp* | atm* | ptm* | br* | wwan* | l2tp* | pptp*)
			break
			;;
		*.*)
			break
			;;
		*)
			case $lowlayer in
			Device.Ethernet.VLANTermination.*)
				cmclient -v vlan -u "$4" GETV $lowlayer.VLANID
				suffix=".$vlan$suffix"
				help_active_lowlayer lowlayer $lowlayer $4
				;;
			Device.Ethernet.Link.* | Device.PPP.Interface.* | Device.IP.Interface.*)
				help_active_lowlayer lowlayer $lowlayer $4
				;;
			*)
				cmclient -v lowlayer -u "$4" GETV "$lowlayer.LowerLayers"
				;;
			esac
			;;
		esac
	done
	[ ${#ifname} -gt 0 ] && eval $1='$ifname$suffix' || eval $1=''
}
help_lowest_ifname_get() {
	[ "$1" != "_o" ] && local _o
	[ "$1" != "_in" ] && local _in
	_o=$3
	[ ${#_o} -eq 0 ] && _o=${2%%,*}
	while [ ${#_o} -gt 0 ]; do
		case $_o in
		Device.Ethernet.Interface.* | Device.WiFi.SSID.* | Device.PTM.Link.* | Device.ATM.Link.* | Device.DSL.Line.*)
			cmclient -v _in GETV "$_o.Name"
			break
			;;
		Device.Bridging.Bridge.*)
			cmclient -v _in GETV ${_o%%.Port*}.Port.[ManagementPort=true].Name
			break
			;;
		Device.X_ADB_MobileModem.Interface.*)
			cmclient -v _in GETV "Device.Ethernet.Link.[LowerLayers,$_o].Name"
			break
			;;
		esac
		case $_o in
		Device.Ethernet.VLANTermination.* | Device.Ethernet.Link.* | Device.PPP.Interface.* | Device.IP.Interface.*)
			help_active_lowlayer _o $_o $4
			;;
		*)
			cmclient -v _o GETV "$_o.LowerLayers"
			;;
		esac
	done
	eval $1='$_in'
}
help_lowlayer_obj_get() {
	[ "$1" != "_p" ] && local _p
	[ "$1" != "_ll" ] && local _ll
	_p="$3"
	help_active_lowlayer _ll $2
	while [ ${#_ll} -gt 0 ]; do
		case $_ll in
		"$_p" | "$_p".*)
			break
			;;
		*)
			help_active_lowlayer _ll $_ll
			;;
		esac
	done
	eval $1='$_ll'
}
help_ip_interface_get() {
	[ "$1" != "hl" ] && local hl
	[ "$1" != "hls" ] && local hls
	hl=$2
	if [ "${hl%.*}" = "Device.IP.Interface" ]; then
		eval $1='$hl'
		return
	fi
	[ "$1" != "ret" ] && local ret
	ret=''
	while [ ${#hl} -gt 0 ]; do
		for hl in $hl; do
			cmclient -v hl GETV "Device.InterfaceStack.[LowerLayer=$hl].HigherLayer"
			for hl in $hl; do
				if [ "${hl%.*}" = "Device.IP.Interface" ]; then
					case " $ret " in
					*" $hl "*) ;;
					*) ret="${ret:+$ret }$hl" ;;
					esac
					continue
				fi
				hls="${hls:+$hls }$hl"
			done
		done
		hl=$hls
		hls=
	done
	eval $1='$ret'
}
help_ip_interface_get_first() {
	help_ip_interface_get "$@"
	eval for $1 in \$$1\; do break\; done
}
help_find_if_phyiface() {
	[ "$1" != "ifname" ] && local ifname
	case $2 in
	ppp* | atm* | ptm* | br* | eth* | wwan* | l2tp* | pptp*)
		ifname="$2"
		;;
	*.*)
		ifname="$2"
		;;
	*)
		ifname=''
		;;
	esac
	eval $1="$ifname"
}
help_lowlayer_ifname_get_all() {
	[ "$1" != "_o" ] && local _o
	[ "$1" != "_ifs" ] && local _ifs=""
	[ "$1" != "_if" ] && local _if
	[ "$1" != "_lls" ] && local _lls
	[ "$1" != "_ll" ] && local _ll
	[ "$1" != "_vlan" ] && local _vlan
	_lls="$2"
	[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
	IFS=","
	while [ ${#_lls} -gt 0 ]; do
		_o=$_lls
		unset _lls
		for _o in $_o; do
			cmclient -v _if GETV "$_o.Name"
			cmclient -v _ll GETV "$_o.LowerLayers"
			[ ${#_if} -eq 0 -a ${#_ll} -eq 0 ] && continue
			case $_if in
			ppp* | atm* | ptm* | br* | eth* | wwan* | l2tp* | pptp*)
				_ifs=${_ifs:+$_ifs }$_if
				continue
				;;
			*.*)
				_ifs=${_ifs:+$_ifs }$_if
				continue
				;;
			*)
				case $_o in
				Device.Ethernet.VLANTermination.*)
					cmclient -v _vlan GETV $_o.VLANID
					help_lowlayer_ifname_get_all _ll $_ll
					IFS=" "
					for _ll in $_ll; do
						_ifs=${_ifs:+$_ifs }$_ll.$_vlan
					done
					IFS=','
					;;
				*)
					[ ${#_ll} -ne 0 ] && _lls="${_lls:+$_lls,}$_ll"
					;;
				esac
				;;
			esac
		done
	done
	[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
	eval $1='$_ifs'
}
