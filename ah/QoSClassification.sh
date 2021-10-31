#!/bin/sh
AH_NAME="QoSClassification"
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
. /etc/ah/helper_serialize.sh
. /etc/ah/helper_brfilter.sh
. /etc/ah/target.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/IPv6_helper_firewall.sh
trigger_policy() {
	cmclient -v fPolicy GETV "$obj.ForwardingPolicy"
	if [ "$fPolicy" != "0" ]; then
		cmclient -v fPolicyRef GETV "Device.Routing.Router.1.IPv4Forwarding.$fPolicy.ForwardingPolicy"
		if [ "$fPolicyRef" != "-1" ]; then
			cmclient SET -u "$AH_NAME" "Device.Routing.Router.1.IPv4Forwarding.$fPolicy.ForwardingPolicy" "-1" >/dev/null
			cmclient SET -u "$AH_NAME" "Device.Routing.Router.1.IPv4Forwarding.$fPolicy.ForwardingPolicy" "$fPolicyRef" >/dev/null
		fi
	fi
}
check_interface_in_hwswitch() {
	del_obj="$1"
	cmclient -v bridge_port GET QoS.Classification.[Enable=true].*.Interface
	for obj_intf in $bridge_port; do
		cur_obj=${obj_intf%;*}
		interface=${obj_intf#$cur_obj;}
		cur_obj=${cur_obj%.*}
		[ "$cur_obj" = "$del_obj" ] && continue
		[ -z "$interface" -o "$interface" = "X_ADB_Local" ] && continue
		help_lowlayer_ifname_get "low_layer" "$interface"
		case "$low_layer" in
		br*) ;;

		*)
			help_is_hw_bridged $low_layer && return 0
			;;
		esac
	done
	return 1
}
if [ "${user%%_*}" = "init" ]; then
	user=${user#init_}
	init=1
fi
subOp="$1"
ifRefresh="$2"
[ -n "$obj" -a "${obj%.*}" != "Device.QoS.Classification" ] && subOp="refresh" && ifRefresh="$obj"
[ "$op" != "g" ] && [ "$setX_ADB_TR098Reference" != "1" ] && [ "$subOp" != "init" ] && [ "$init" != "1" ] && while [ -d /tmp/init_iptables ]; do sleep 0.1; done
case "$subOp" in
init)
	cmclient SETE "Device.QoS.Classification.[Enable=true].Status" Enabled
	help_iptables_all -t filter
	maxorder=0
	cmclient -v i GETV "Device.QoS.Classification.*.Order"
	for i in $i; do
		[ $i -gt $maxorder ] && maxorder=$i
	done
	i=1
	nextorder=1
	while [ $i -le $maxorder ]; do
		cmclient -v o GETO "Device.QoS.Classification.[Order=$i]"
		i=$((i + 1))
		[ -z "$o" ] && continue
		[ $nextorder -ne $i ] && cmclient SETE "$o.Order" "$nextorder"
		nextorder=$((nextorder + 1))
		cmclient -v e GETV "$o.Enable"
		[ "$e" = "true" ] || continue
		cmclient -v type GETV $o.X_ADB_InterfaceType
		if [ "$type" = "Ingress" ]; then
			cmclient -v interface GETV $o.Interface
			if [ "$interface" = "X_ADB_Local" ]; then
				table="mangle"
				stage="LocalClasses"
			else
				table="mangle"
				stage="Classes"
			fi
		else
			table="mangle"
			stage="OutputClasses"
		fi
		help_iptables_all -t "$table" -N "$o"s
		help_iptables_all -t "$table" -A "$stage" -j "$o"s
	done
	ebtables -t broute -N QoS.Classification -P RETURN
	ebtables -t broute -I BROUTING 1 -j QoS.Classification
	cmclient -v i GETO "Device.QoS.Classification.[Enable=true]"
	for i in $i; do
		setm_params="${setm_params:+$setm_params	}$i.Enable=true"
	done
	[ -n "$setm_params" ] && cmclient SETM -u "init_${tmpiptablesprefix##*/}" "$setm_params"
	if check_interface_in_hwswitch; then
		cmclient SET Device.Bridging.X_ADB_HWSwitch.DisableRequest Device.QoS.Classification
	fi
	exit 0
	;;
refresh)
	for x in mangle filter; do
		help_iptables_all -t $x
	done
	cmclient -v i GETO "Device.QoS.Classification.[Enable=true].[Interface>$ifRefresh].[AllInterfaces=false]"
	for i in $i; do
		setm_params="${setm_params:+$setm_params	}$i.Enable=true"
	done
	[ -n "$setm_params" ] && cmclient SETM -u "init_${tmpiptablesprefix##*/}" "$setm_params" >/dev/null
	if check_interface_in_hwswitch; then
		cmclient SET Device.Bridging.X_ADB_HWSwitch.DisableRequest Device.QoS.Classification
	fi
	exit 0
	;;
esac
[ "$op" != "g" ] && help_serialize ${AH_NAME} >/dev/null
if [ "$newX_ADB_InterfaceType" = "Ingress" ]; then
	if [ "$newInterface" = "X_ADB_Local" ]; then
		table="mangle"
		stage="LocalClasses"
	else
		table="mangle"
		stage="Classes"
	fi
	ifopt="-i"
	physdir="in"
else
	table="mangle"
	stage="OutputClasses"
	ifopt="-o"
	physdir="out"
fi
case "$op" in
a)
	maxorder=0
	cmclient -v i GETV "Device.QoS.Classification.*.Order"
	for i in $i; do
		if [ $i -gt $maxorder ]; then
			maxorder=$i
		fi
	done
	maxorder=$((maxorder + 1))
	cmclient SETE "$obj".Order $maxorder
	exit 0
	;;
d)
	if [ "$oldEnable" = "true" ]; then
		cmclient -v fPolicy GETV "$obj.ForwardingPolicy"
		if [ $fPolicy -ne 0 ]; then
			cmclient -v qosRefs GETO Device.QoS.**.[ForwardingPolicy="$fPolicy"]
			cnt=0
			for i in $qosRefs; do
				cnt=$((cnt + 1))
			done
			if [ $cnt -le 1 ]; then
				cmclient SET -u "$AH_NAME" "Device.Routing.Router.1.IPv4Forwarding.$fPolicy.ForwardingPolicy" "-1"
			fi
		fi
		help_iptables_all -t "$table" -D "$stage" -j "$obj"s
		help_iptables_all -t mangle -F "$obj"
		help_iptables_all -t mangle -F "$obj"_
		help_iptables_all -t mangle -F "$obj"s
		help_iptables_all -t filter -F "$obj"
		help_iptables_all -t mangle -X "$obj"
		help_iptables_all -t mangle -X "$obj"_
		help_iptables_all -t mangle -X "$obj"s
		help_iptables_all -t filter -X "$obj"
	fi
	cmclient -v i GETO "Device.QoS.Classification.*.[Order+$oldOrder]"
	for i in $i; do
		cmclient -v order GETV "$i".Order
		cmclient SETE "$i.Order" "$((order - 1))"
	done
	cmclient SET Device.X_ADB_FastForward.Yatta.FlushConnections true
	if ! check_interface_in_hwswitch "$obj"; then
		cmclient SET Device.Bridging.X_ADB_HWSwitch.EnableRequest Device.QoS.Classification
	fi
	exit 0
	;;
esac
if [ "$newEnable" = "false" ] && [ $changedEnable -eq 0 ] && [ -n "$newOrder" ] && [ $changedOrder -eq 0 ]; then
	exit 0
fi
orderDone=0
if [ $changedEnable -eq 0 ] && [ $changedOrder -eq 1 ]; then
	help_sort_orders "$obj" "$oldOrder" "$newOrder" "$AH_NAME"
fi
isEnslaved=0
if [ "${newInterface%%.[0-9]*}" != "Device.Bridging.Bridge" ]; then
	cmclient -v upperLayers GETO Device.**.[LowerLayers="$newInterface"]
	for l in $upperLayers; do
		if [ "${l%%.[0-9]*}" = "Device.Bridging.Bridge" ]; then
			this_bridge=${l%.Port.*}
			cmclient -v bridge_enabled GETV "$this_bridge.Port.[ManagementPort=true].Enable"
			[ "$bridge_enabled" = "true" ] && isEnslaved=1
		fi
	done
fi
if [ $setEnable -eq 0 ] && ! help_is_changed AllInterfaces App DestIP DestIPExclude DestMACAddress DestMACExclude DestMACMask \
	DestMask DestPort DestPortExclude DestPortRangeMax DSCPCheck DSCPExclude DSCPMark Enable EthernetPriorityCheck \
	EthernetPriorityExclude EthernetPriorityMark Ethertype EthertypeExclude ForwardingPolicy Interface IPLengthExclude \
	IPLengthMax IPLengthMin Order Policer Protocol ProtocolExclude SourceIP SourceIPExclude SourceMACAddress \
	X_ADB_Cascade X_ADB_ForwardingPolicyMask \
	SourceMACExclude SourceMACMask SourceMask SourcePort SourcePortExclude SourcePortRangeMax SSAP SSAPExclude TCPACK \
	TCPACKExclude TrafficClass VLANIDCheck VLANIDExclude X_ADB_ConnectionRateLimit X_ADB_ConnectionRateLimitBurst \
	X_ADB_ConnectionRateLimitUnit X_ADB_DateStart X_ADB_DateStop X_ADB_ExtraDestPorts X_ADB_ExtraSourcePorts \
	X_ADB_InterfaceType X_ADB_TimeStart X_ADB_TimeStop X_ADB_WeekDays X_ADB_IPVersion X_ADB_NfMarkCheck \
	X_ADB_NfMarkExclude \
	SourceClientID SourceClientIDExclude SourceUserClassID SourceUserClassIDExclude SourceVendorClassID \
	SourceVendorClassIDExclude SourceVendorClassIDMode DestClientID DestClientIDExclude DestUserClassID \
	DestUserClassIDExclude DestVendorClassID DestVendorClassIDExclude DestVendorClassIDMode; then
	exit 0
fi
ebtables -t broute -F "$obj" 2>/dev/null
ebtables -t broute -F "$obj"s 2>/dev/null
ebtables -t broute -D QoS.Classification -j "$obj" 2>/dev/null
ebtables -t broute -D QoS.Classification -j "$obj"s 2>/dev/null
ebtables -t broute -X "$obj" 2>/dev/null
ebtables -t broute -X "$obj"s 2>/dev/null
ebtables -t broute -X "$obj"_OUT 2>/dev/null
if [ "$newEnable" = "false" ]; then
	if [ $changedEnable -eq 1 ]; then
		trigger_policy
		help_iptables_all -t "$table" -D "$stage" -j "$obj"s
		help_iptables_all -t mangle -F "$obj"
		help_iptables_all -t mangle -F "$obj"_
		help_iptables_all -t mangle -F "$obj"s
		help_iptables_all -t filter -F "$obj"
		help_iptables_all -t mangle -X "$obj"
		help_iptables_all -t mangle -X "$obj"_
		help_iptables_all -t mangle -X "$obj"s
		help_iptables_all -t filter -X "$obj"
		cmclient SETE "$obj".Status Disabled
		cmclient SET Device.X_ADB_FastForward.Yatta.FlushConnections true
	fi
	if ! check_interface_in_hwswitch $obj; then
		cmclient SET Device.Bridging.X_ADB_HWSwitch.EnableRequest Device.QoS.Classification
	fi
	exit 0
else
	if [ $changedEnable -eq 1 -o $changedOrder -eq 1 ]; then
		trigger_policy
		help_iptables_all -t mangle -N "$obj"
		help_iptables_all -t mangle -N "$obj"_
		help_iptables_all -t mangle -N "$obj"s
		help_iptables_all -t filter -N "$obj"
		pos=1
		if [ $newOrder -gt 1 ]; then
			cmclient -v r GETO Device.QoS.Classification.[Enable=true].[Order-$newOrder]
			for r in $r; do
				cmclient -v exRuleIface GETV "$r".Interface
				cmclient -v exRuleIfaceType GETV "$r".X_ADB_InterfaceType
				[ "$newX_ADB_InterfaceType" != "$exRuleIfaceType" ] && continue
				if [ "$newInterface" = "X_ADB_Local" ]; then
					[ "$exRuleIface" != "X_ADB_Local" ] && continue
				else
					[ "$exRuleIface" = "X_ADB_Local" ] && continue
				fi
				pos=$((pos + 1))
			done
		fi
		[ $changedEnable -eq 0 ] && help_iptables_all -t "$table" -D "$stage" -j "$obj"s
		help_iptables_all -t "$table" -I "$stage" "$pos" -j "$obj"s
	else
		help_iptables_all -t mangle -F "$obj"
		help_iptables_all -t mangle -F "$obj"_
		help_iptables_all -t mangle -F "$obj"s
		help_iptables_all -t filter -F "$obj"
	fi
fi
ebtmatch=0
if [ "$stage" = "LocalClasses" ]; then
	cmclient -v GUIPort GETV Device.UserInterface.X_ADB_LocalAccess.Port
	if [ -n "$GUIPort" ]; then
		help_iptables_all -t "$table" -A "$obj" -m state --state ESTABLISHED,RELATED -p tcp --sport "$GUIPort" -j RETURN
	fi
fi
if [ "$newAllInterfaces" = "false" ] && [ "$newInterface" != "X_ADB_Local" ]; then
	help_lowlayer_ifname_get ifname "$newInterface"
	if [ -z "$ifname" ]; then
		help_iptables_all -t "$table" -A "$obj" -j RETURN
	else
		if [ $isEnslaved -eq 1 ]; then
			[ "$physdir" = out ] && pd_is_br="--physdev-is-bridged" || pd_is_br=
			help_iptables_all -t "$table" -A "$obj" -m physdev ! --physdev-$physdir "$ifname" $pd_is_br -j RETURN
		else
			help_iptables_all -t "$table" -A "$obj" ! $ifopt "$ifname" -j RETURN
		fi
	fi
fi
case "$newX_ADB_IPVersion" in
4) help_iptables_all() { help_iptables "$@"; } ;;
6) help_iptables_all() { help_ip6tables "$@"; } ;;
*)
	case "$newSourceIP" in
	*:*)
		case "$newDestIP" in
		*:* | '')
			help_iptables_all() { help_ip6tables "$@"; }
			;;
		*)
			cmclient SETE "$obj".Status Error_Misconfigured
			exit 0
			;;
		esac
		;;
	'')
		case "$newDestIP" in
		*:*) help_iptables_all() { help_ip6tables "$@"; } ;;
		'') ;;
		*) help_iptables_all() { help_iptables "$@"; } ;;
		esac
		;;
	*)
		case "$newDestIP" in
		*:*)
			cmclient SETE "$obj".Status Error_Misconfigured
			exit 0
			;;
		*)
			help_iptables_all() { help_iptables "$@"; }
			;;
		esac
		;;
	esac
	;;
esac
cmclient SETE "$obj".Status Enabled
if [ -n "$newDestIP" ]; then
	if [ "$newDestIPExclude" = "true" ]; then
		if [ -n "$newDestMask" ]; then
			help_iptables_all -t "$table" -A "$obj" -d "$newDestIP"/"$newDestMask" -j RETURN
		else
			help_iptables_all -t "$table" -A "$obj" -d "$newDestIP" -j RETURN
		fi
	else
		if [ -n "$newDestMask" ]; then
			help_iptables_all -t "$table" -A "$obj" ! -d "$newDestIP"/"$newDestMask" -j RETURN
		else
			help_iptables_all -t "$table" -A "$obj" ! -d "$newDestIP" -j RETURN
		fi
	fi
fi
if [ -n "$newSourceIP" ]; then
	set -f
	IFS=","
	set -- $newSourceIP
	i=1
	for srcip; do
		set -- $newSourceMask
		eval srcmask=\$$i
		if [ "$newSourceIPExclude" = "true" ]; then
			help_iptables_all -t "$table" -A "$obj"s -s "$srcip/${srcmask:-32}" -j RETURN
		else
			help_iptables_all -t "$table" -A "$obj"s -s "$srcip/${srcmask:-32}" -g "$obj"
		fi
		i=$((i + 1))
	done
	if [ "$newSourceIPExclude" = "true" ]; then
		help_iptables_all -t "$table" -A "$obj"s -g "$obj"
	else
		help_iptables_all -t "$table" -A "$obj"s -j RETURN
	fi
	set +f
	unset IFS
else
	help_iptables_all -t "$table" -A "$obj"s -g "$obj"
fi
if [ -n "$newProtocol" ] && [ "$newProtocol" != "-1" ]; then
	if [ "$newProtocolExclude" = "true" ]; then
		help_iptables_all -t "$table" -A "$obj" -p "$newProtocol" -j RETURN
	else
		help_iptables_all -t "$table" -A "$obj" ! -p "$newProtocol" -j RETURN
	fi
fi
if [ -n "$newDestPort" ] && [ "$newDestPort" != "-1" ]; then
	portcmd="$newDestPort"
	if [ -n "$newDestPortRangeMax" ] && [ "$newDestPortRangeMax" != "-1" ] && [ $newDestPortRangeMax -gt $newDestPort ]; then
		portcmd="$portcmd:$newDestPortRangeMax"
		[ "$newDestPortExclude" = "true" ] && portcmd="-m multiport --dports $portcmd" || portcmd="-m multiport ! --dports $portcmd"
		[ -n "$newX_ADB_ExtraDestPorts" ] && portcmd="$portcmd,$newX_ADB_ExtraDestPorts"
	else
		if [ -n "$newX_ADB_ExtraDestPorts" ]; then
			[ "$newDestPortExclude" = "true" ] && portcmd="-m multiport --dports $portcmd,$newX_ADB_ExtraDestPorts" ||
				portcmd="-m multiport ! --dports $portcmd,$newX_ADB_ExtraDestPorts"
		else
			[ "$newDestPortExclude" = "true" ] && portcmd="--dport $portcmd" || portcmd="! --dport $portcmd"
		fi
	fi
	help_iptables_all -t "$table" -A "$obj" -p tcp "$portcmd" -j RETURN
	help_iptables_all -t "$table" -A "$obj" -p udp "$portcmd" -j RETURN
fi
if [ -n "$newSourcePort" ] && [ "$newSourcePort" != "-1" ]; then
	portcmd="$newSourcePort"
	if [ -n "$newSourcePortRangeMax" ] && [ "$newSourcePortRangeMax" != "-1" ] && [ $newSourcePortRangeMax -gt $newSourcePort ]; then
		portcmd="$portcmd:$newSourcePortRangeMax"
		[ "$newSourcePortExclude" = "true" ] && portcmd="-m multiport --sports $portcmd" || portcmd="-m multiport ! --sports $portcmd"
		[ -n "$newX_ADB_ExtraSourcePorts" ] && portcmd="$portcmd,$newX_ADB_ExtraSourcePorts"
	else
		if [ -n "$newX_ADB_ExtraSourcePorts" ]; then
			[ "$newSourcePortExclude" = "true" ] && portcmd="-m multiport --sports $portcmd,$newX_ADB_ExtraSourcePorts" ||
				portcmd="-m multiport ! --sports $portcmd,$newX_ADB_ExtraSourcePorts"
		else
			[ "$newSourcePortExclude" = "true" ] && portcmd="--sport $portcmd" || portcmd="! --sport $portcmd"
		fi
	fi
	help_iptables_all -t "$table" -A "$obj" -p tcp "$portcmd" -j RETURN
	help_iptables_all -t "$table" -A "$obj" -p udp "$portcmd" -j RETURN
fi
if [ -n "$newX_ADB_DateStart" ]; then
	case "$newX_ADB_DateStart" in
	*Z)
		datestart=${newX_ADB_DateStart%Z}
		datestartutc="--utc"
		;;
	*)
		datestart=$newX_ADB_DateStart
		datestartutc=""
		;;
	esac
	help_iptables_all -t "$table" -A "$obj" -m time --datestop "$datestart" $datestartutc -j RETURN
fi
if [ -n "$newX_ADB_DateStop" ]; then
	case "$newX_ADB_DateStop" in
	*Z)
		datestop=${newX_ADB_DateStop%Z}
		datestoputc="--utc"
		;;
	*)
		datestop=$newX_ADB_DateStop
		datestoputc=""
		;;
	esac
	help_iptables_all -t "$table" -A "$obj" -m time --datestart "$datestop" $datestoputc -j RETURN
fi
if [ -n "$newX_ADB_TimeStop" ]; then
	if [ -n "$newX_ADB_TimeStart" ]; then
		timestop=$(gmtoff $newX_ADB_TimeStop)
		timestart=$(gmtoff $newX_ADB_TimeStart)
		if [ $timestart -lt $timestop ]; then
			help_iptables_all -t "$table" -A "$obj" -m time --timestop "$newX_ADB_TimeStart" -j RETURN
			help_iptables_all -t "$table" -A "$obj" -m time --timestart "$newX_ADB_TimeStop" -j RETURN
		else
			help_iptables_all -t "$table" -A "$obj" -m time --timestart "$newX_ADB_TimeStop" --timestop "$newX_ADB_TimeStart" -j RETURN
		fi
	else
		help_iptables_all -t "$table" -A "$obj" -m time --timestart "$newX_ADB_TimeStop" -j RETURN
	fi
else
	if [ -n "$newX_ADB_TimeStart" ]; then
		help_iptables_all -t "$table" -A "$obj" -m time --timestop "$newX_ADB_TimeStart" -j RETURN
	fi
fi
if [ -n "$newX_ADB_NfMarkCheck" ] && [ "$newX_ADB_NfMarkCheck" != "-1" ]; then
	if [ "$newX_ADB_NfMarkExclude" = "false" ]; then
		help_iptables_all -t "$table" -A "$obj" -m mark ! --mark $((newX_ADB_NfMarkCheck * 16777216))/0xFF000000 -j RETURN
	else
		help_iptables_all -t "$table" -A "$obj" -m mark --mark $((newX_ADB_NfMarkCheck * 16777216))/0xFF000000 -j RETURN
	fi
fi
if [ -n "$newX_ADB_WeekDays" ]; then
	help_iptables_all -t "$table" -A "$obj" -m time ! --weekdays "$newX_ADB_WeekDays" -j RETURN
fi
if [ -n "$newSourceMACAddress" ]; then
	ebtmatch=1
fi
if [ -n "$newDestMACAddress" ]; then
	ebtmatch=1
	if [ "$newDestMACExclude" = "true" ]; then
		if [ -n "$newDestMACMask" ]; then
			ebt_destmacaddr_rule="ebtables -t broute -A $obj -d $newDestMACAddress/$newDestMACMask -j RETURN"
		else
			ebt_destmacaddr_rule="ebtables -t broute -A $obj -d $newDestMACAddress -j RETURN"
		fi
	else
		if [ -n "$newDestMACMask" ]; then
			ebt_destmacaddr_rule="ebtables -t broute -A $obj ! -d $newDestMACAddress/$newDestMACMask -j RETURN"
		else
			ebt_destmacaddr_rule="ebtables -t broute -A $obj ! -d $newDestMACAddress -j RETURN"
		fi
	fi
fi
for _param_name in SourceClientID SourceUserClassID SourceVendorClassID \
	DestClientID DestUserClassID DestVendorClassID; do
	eval param=\$new${_param_name}
	if [ -n "$param" ]; then
		ebtmatch=1
		dhcp_exclude="!"
		eval param_exclude=\$new${_param_name}Exclude
		[ "$param_exclude" = "true" ] && dhcp_exclude=""
		case "$_param_name" in
		*"Source"*) dhcp_flags="src" ;;
		*"Dest"*) dhcp_flags="dst" ;;
		esac
		case "$_param_name" in
		*"ClientID"*) dhcp_tag="61" ;;
		*"UserClassID"*) dhcp_tag="77" ;;
		*"VendorClassID"*) dhcp_tag="60" ;;
		esac
		if [ "$dhcp_tag" = "60" ]; then
			eval param_mode=\$new${_param_name}Mode
			case "$param_mode" in
			"Substring") dhcp_mode="substr" ;;
			*) dhcp_mode="" ;;
			esac
			[ -n "$dhcp_mode" ] && dhcp_flags="${dhcp_flags},${dhcp_mode}"
		else
			dhcp_flags="${dhcp_flags},hex"
		fi
		param_rule=ebt_${_param_name}_rule
		eval $param_rule=\"ebtables -t broute -A ${obj} -l dhcp --dhcp-timeout 0 --dhcp-tag ${dhcp_tag} ${dhcp_exclude} --dhcp-value ${param} --dhcp-flags ${dhcp_flags} -j RETURN\"
	fi
done
if [ -n "$newEthertype" ] && [ "$newEthertype" != "-1" ]; then
	ebtmatch=1
	if [ "$newEthertypeExclude" = "true" ]; then
		ebt_ethertype_rule="ebtables -t broute -A $obj -p $(printf %x $newEthertype) -j RETURN"
	else
		ebt_ethertype_rule="ebtables -t broute -A $obj ! -p $(printf %x $newEthertype) -j RETURN"
	fi
fi
if [ -n "$newSSAP" ] && [ "$newSSAP" != "-1" ]; then
	ebtmatch=1
	if [ "$newSSAPExclude" = "true" ]; then
		ebt_ssap_rule="ebtables -t broute -A $obj -p LENGTH --802_3-sap $newSSAP -j RETURN"
	else
		ebt_ssap_rule="ebtables -t broute -A $obj -p LENGTH --802_3-sap ! $newSSAP -j RETURN"
	fi
fi
if [ -n "$newTCPACK" ] && [ "$newTCPACK" = "true" ]; then
	if [ "$newTCPACKExclude" = "true" ]; then
		help_iptables_all -t "$table" -A "$obj" -p tcp --tcp-flags ACK ACK -j RETURN
	else
		help_iptables_all -t "$table" -A "$obj" -p tcp --tcp-flags ACK NONE -j RETURN
	fi
fi
if [ -n "$newIPLengthMin" ] && [ $newIPLengthMin -gt 0 ]; then
	if [ "$newIPLengthExclude" = "true" ]; then
		if [ "$newIPLengthMax" -ne 0 ]; then
			help_iptables_all -t "$table" -A "$obj" -m length --length "$newIPLengthMin":"$newIPLengthMax" -j RETURN
		else
			help_iptables_all -t "$table" -A "$obj" -m length --length "$newIPLengthMin": -j RETURN
		fi
	else
		if [ "$newIPLengthMax" -ne 0 ]; then
			help_iptables_all -t "$table" -A "$obj" -m length ! --length "$newIPLengthMin":"$newIPLengthMax" -j RETURN
		else
			help_iptables_all -t "$table" -A "$obj" -m length ! --length "$newIPLengthMin": -j RETURN
		fi
	fi
elif [ -n "$newIPLengthMax" ] && [ $newIPLengthMax -gt 0 ]; then
	if [ "$newIPLengthExclude" = "true" ]; then
		help_iptables_all -t "$table" -A "$obj" -m length --length 0:"$newIPLengthMax" -j RETURN
	else
		help_iptables_all -t "$table" -A "$obj" -m length ! --length 0:"$newIPLengthMax" -j RETURN
	fi
fi
if [ -n "$newDSCPCheck" ] && [ "$newDSCPCheck" != "-1" ]; then
	if [ $newDSCPCheck -lt 8 ]; then
		cscp="CS0""$newDSCPCheck"
	fi
	if [ "$newDSCPExclude" = "true" ]; then
		if [ -n "$cscp" ]; then
			help_iptables_all -t "$table" -A "$obj" -m dscp --dscp-class "$cscp" -j RETURN
		else
			help_iptables_all -t "$table" -A "$obj" -m dscp --dscp "$newDSCPCheck" -j RETURN
		fi
	else
		if [ -n "$cscp" ]; then
			help_iptables_all -t "$table" -A "$obj" -m dscp ! --dscp-class "$cscp" -j RETURN
		else
			help_iptables_all -t "$table" -A "$obj" -m dscp ! --dscp "$newDSCPCheck" -j RETURN
		fi
	fi
fi
if [ -n "$newEthernetPriorityCheck" ] && [ "$newEthernetPriorityCheck" != "-1" ]; then
	ebtmatch=1
	if [ "$newEthernetPriorityExclude" = "true" ]; then
		ebt_vlanpriocheck_rule2="ebtables -t broute -A $obj -p 0x8100 --vlan-prio $newEthernetPriorityCheck -j RETURN"
	else
		ebt_vlanpriocheck_rule1="ebtables -t broute -A $obj -p ! 0x8100 -j RETURN"
		ebt_vlanpriocheck_rule2="ebtables -t broute -A $obj -p 0x8100 --vlan-prio ! $newEthernetPriorityCheck -j RETURN"
	fi
fi
if [ -n "$newVLANIDCheck" ] && [ "$newVLANIDCheck" != "-1" ]; then
	ebtmatch=1
	if [ "$newVLANIDExclude" = "true" ]; then
		ebt_vlanidcheck_rule2="ebtables -t broute -A $obj -p 0x8100 --vlan-id $newVLANIDCheck -j RETURN"
	else
		ebt_vlanidcheck_rule1="ebtables -t broute -A $obj -p ! 0x8100 -j RETURN"
		ebt_vlanidcheck_rule2="ebtables -t broute -A $obj -p 0x8100 --vlan-id ! $newVLANIDCheck -j RETURN"
	fi
fi
if [ -n "$newApp" ] && [ "$newApp" != "-1" ]; then
	cmclient -v dscpmark_app GETV "$newApp".DefaultDSCPMark
	if [ "$dscpmark_app" != "-1" ]; then
		dscpmark="$dscpmark_app"
	fi
	cmclient -v vlanpriomark_app GETV "$newApp".DefaultEthernetPriorityMark
	if [ "$vlanpriomark_app" != "-1" ]; then
		vlanpriomark="$vlanpriomark_app"
	fi
else
	dscpmark=$newDSCPMark
	vlanpriomark=$newEthernetPriorityMark
fi
if [ -n "$dscpmark" ] && [ "$dscpmark" != "-1" ]; then
	if [ "$dscpmark" = "-2" ]; then
		ebt_dscp_rule1="ebtables -t broute -A $obj -p 0x8100 --vlan-prio 0 -j mark --set-mark 0x00000000"
		ebt_dscp_rule2="ebtables -t broute -A $obj -p 0x8100 --vlan-prio 1 -j mark --set-mark 0x00010000"
		ebt_dscp_rule3="ebtables -t broute -A $obj -p 0x8100 --vlan-prio 2 -j mark --set-mark 0x00020000"
		ebt_dscp_rule4="ebtables -t broute -A $obj -p 0x8100 --vlan-prio 3 -j mark --set-mark 0x00030000"
		ebt_dscp_rule5="ebtables -t broute -A $obj -p 0x8100 --vlan-prio 4 -j mark --set-mark 0x00040000"
		ebt_dscp_rule6="ebtables -t broute -A $obj -p 0x8100 --vlan-prio 5 -j mark --set-mark 0x00050000"
		ebt_dscp_rule7="ebtables -t broute -A $obj -p 0x8100 --vlan-prio 6 -j mark --set-mark 0x00060000"
		ebt_dscp_rule8="ebtables -t broute -A $obj -p 0x8100 --vlan-prio 7 -j mark --set-mark 0x00070000"
		dscp_rule1="help_iptables_all -t mangle -A $obj -m mark --mark 0x00000000/0x00070000 -j DSCP --set-dscp 0"
		dscp_rule2="help_iptables_all -t mangle -A $obj -m mark --mark 0x00010000/0x00070000 -j DSCP --set-dscp 0"
		dscp_rule3="help_iptables_all -t mangle -A $obj -m mark --mark 0x00020000/0x00070000 -j DSCP --set-dscp 0"
		dscp_rule4="help_iptables_all -t mangle -A $obj -m mark --mark 0x00030000/0x00070000 -j DSCP --set-dscp 0x08"
		dscp_rule5="help_iptables_all -t mangle -A $obj -m mark --mark 0x00040000/0x00070000 -j DSCP --set-dscp 0x10"
		dscp_rule6="help_iptables_all -t mangle -A $obj -m mark --mark 0x00050000/0x00070000 -j DSCP --set-dscp 0x18"
		dscp_rule7="help_iptables_all -t mangle -A $obj -m mark --mark 0x00060000/0x00070000 -j DSCP --set-dscp 0x28"
		dscp_rule8="help_iptables_all -t mangle -A $obj -m mark --mark 0x00070000/0x00070000 -j DSCP --set-dscp 0x38"
	else
		dscp_rule="help_iptables_all -t $table -A $obj -j DSCP --set-dscp $dscpmark"
	fi
fi
if [ -n "$vlanpriomark" ] && [ "$vlanpriomark" != "-1" ]; then
	if [ "$vlanpriomark" = "-2" ]; then
		vlan_rule1="help_iptables_all -t $table -A $obj -m dscp --dscp 0x0 -j MARK --or-mark 0x00600000"
		vlan_rule2="help_iptables_all -t $table -A $obj -m dscp --dscp 0x0e -j MARK --or-mark 0x00600000"
		vlan_rule3="help_iptables_all -t $table -A $obj -m dscp --dscp 0x0c -j MARK --or-mark 0x00600000"
		vlan_rule4="help_iptables_all -t $table -A $obj -m dscp --dscp 0x0a -j MARK --or-mark 0x00600000"
		vlan_rule5="help_iptables_all -t $table -A $obj -m dscp --dscp 0x08 -j MARK --or-mark 0x00600000"
		vlan_rule6="help_iptables_all -t $table -A $obj -m dscp --dscp 0x16 -j MARK --or-mark 0x00800000"
		vlan_rule7="help_iptables_all -t $table -A $obj -m dscp --dscp 0x14 -j MARK --or-mark 0x00800000"
		vlan_rule8="help_iptables_all -t $table -A $obj -m dscp --dscp 0x12 -j MARK --or-mark 0x00800000"
		vlan_rule9="help_iptables_all -t $table -A $obj -m dscp --dscp 0x10 -j MARK --or-mark 0x00800000"
		vlan_rule10="help_iptables_all -t $table -A $obj -m dscp --dscp 0x1e -j MARK --or-mark 0x00A00000"
		vlan_rule11="help_iptables_all -t $table -A $obj -m dscp --dscp 0x1c -j MARK --or-mark 0x00A00000"
		vlan_rule12="help_iptables_all -t $table -A $obj -m dscp --dscp 0x1a -j MARK --or-mark 0x00A00000"
		vlan_rule13="help_iptables_all -t $table -A $obj -m dscp --dscp 0x18 -j MARK --or-mark 0x00A00000"
		vlan_rule14="help_iptables_all -t $table -A $obj -m dscp --dscp 0x26 -j MARK --or-mark 0x00C00000"
		vlan_rule15="help_iptables_all -t $table -A $obj -m dscp --dscp 0x24 -j MARK --or-mark 0x00C00000"
		vlan_rule16="help_iptables_all -t $table -A $obj -m dscp --dscp 0x22 -j MARK --or-mark 0x00C00000"
		vlan_rule17="help_iptables_all -t $table -A $obj -m dscp --dscp 0x20 -j MARK --or-mark 0x00C00000"
		vlan_rule18="help_iptables_all -t $table -A $obj -m dscp --dscp 0x2e -j MARK --or-mark 0x00C00000"
		vlan_rule19="help_iptables_all -t $table -A $obj -m dscp --dscp 0x28 -j MARK --or-mark 0x00C00000"
		vlan_rule20="help_iptables_all -t $table -A $obj -m dscp --dscp 0x30 -j MARK --or-mark 0x00E00000"
		vlan_rule21="help_iptables_all -t $table -A $obj -m dscp --dscp 0x38 -j MARK --or-mark 0x00E00000"
	else
		vlan_rule="help_iptables_all -t $table -A $obj -j MARK --set-mark $((vlanpriomark * 2097152))/0x00E00000"
		if [ "$stage" = "OutputClasses" ]; then
			vlan_rule1="help_iptables_all -t $table -A $obj -m mark --mark $((vlanpriomark * 2097152))/0x00E00000 -j CLASSIFY --set-class 0:$vlanpriomark"
		fi
	fi
fi
if [ -n "$newX_ADB_ConnectionRateLimit" ] && [ "$newX_ADB_ConnectionRateLimit" != "0" ]; then
	if [ -z "$newX_ADB_ConnectionRateLimitUnit" ]; then
		connrateunit_="s"
	elif [ "$newX_ADB_ConnectionRateLimitUnit" = "Seconds" ]; then
		connrateunit_="s"
	elif [ "$newX_ADB_ConnectionRateLimitUnit" = "Minutes" ]; then
		connrateunit_="m"
	elif [ "$newX_ADB_ConnectionRateLimitUnit" = "Hours" ]; then
		connrateunit_="h"
	elif [ "$newX_ADB_ConnectionRateLimitUnit" = "Days" ]; then
		connrateunit_="d"
	fi
	help_iptables_all -t "$table" -N "$obj"_
	help_iptables_all -t "$table" -A "$obj"_ -m state --state NEW,INVALID,UNTRACKED \
		-m limit --limit "$newX_ADB_ConnectionRateLimit"/"$connrateunit_" --limit-burst "${newX_ADB_ConnectionRateLimitBurst:-5}" -j RETURN
	help_iptables_all -t "$table" -A "$obj"_ -j DROP
	help_iptables_all -t "$table" -A "$obj" -j "$obj"_
fi
if [ $ebtmatch -eq 1 ]; then
	pos=1
	exEBTRulesDump=$(ebtables -t broute -L QoS.Classification)
	cmclient -v r GETO "Device.QoS.Classification.[Enable=true].[Order-$newOrder]"
	for r in $r; do
		for rd in $exEBTRulesDump; do
			if [ "$rd" = "$r"s ]; then
				pos=$((pos + 1))
				break
			fi
		done
	done
	ebtables -t broute -N "$obj"s -P RETURN
	ebtables -t broute -N $obj -P RETURN
	ebtables -t broute -I QoS.Classification $pos -j "$obj"s
	if [ -n "$newSourceMACAddress" ]; then
		set -f
		IFS=","
		set -- $newSourceMACAddress
		i=1
		for srcmac; do
			set -- $newSourceMACMask
			eval srcmacmask=\$$i
			if [ "$newSourceMACExclude" = "true" ]; then
				if [ -n "$srcmacmask" ]; then
					ebtables -t broute -A "$obj"s -s $srcmac/$srcmacmask -j RETURN
				else
					ebtables -t broute -A "$obj"s -s $srcmac -j RETURN
				fi
			else
				if [ -n "$srcmacmask" ]; then
					ebtables -t broute -A "$obj"s -s $srcmac/$srcmacmask -j $obj
				else
					ebtables -t broute -A "$obj"s -s $srcmac -j $obj
				fi
			fi
			i=$((i + 1))
		done
		if [ "$newSourceMACExclude" = "true" ]; then
			ebtables -t broute -A "$obj"s -j "$obj"
		else
			ebtables -t broute -A "$obj"s -j RETURN
		fi
		set +f
		unset IFS
	else
		ebtables -t broute -A "$obj"s -j "$obj"
	fi
	if [ -n "$ebt_destmacaddr_rule" ]; then
		$ebt_destmacaddr_rule
	fi
	for _param_name in SourceClientID SourceUserClassID SourceVendorClassID \
		DestClientID DestUserClassID DestVendorClassID; do
		param_rule=ebt_${_param_name}_rule
		eval [ -n \"\$$param_rule\" ] && eval \$$param_rule
	done
	if [ -n "$ebt_ethertype_rule" ]; then
		$ebt_ethertype_rule
	fi
	if [ -n "$ebt_ssap_rule" ]; then
		$ebt_ssap_rule
	fi
	if [ -n "$ebt_vlanpriocheck_rule2" ]; then
		$ebt_vlanpriocheck_rule1
		$ebt_vlanpriocheck_rule2
	fi
	if [ -n "$ebt_vlanidcheck_rule2" ]; then
		$ebt_vlanidcheck_rule1
		$ebt_vlanidcheck_rule2
	fi
	if [ -n "$ebt_dscp_rule1" ]; then
		$ebt_dscp_rule1
		$ebt_dscp_rule2
		$ebt_dscp_rule3
		$ebt_dscp_rule4
		$ebt_dscp_rule5
		$ebt_dscp_rule6
		$ebt_dscp_rule7
		$ebt_dscp_rule8
	elif [ -n "$ebt_dscp_rule" ]; then
		$ebt_dscp_rule
	fi
	ebtables -t broute -A "$obj" -j mark --set-mark $((pos * 256))
	[ "$newX_ADB_Cascade" = "false" ] && ebtables -t broute -A $obj -j ACCEPT
	help_iptables_all -t mangle -A "$obj" -m mark ! --mark $((pos * 256)) -j RETURN
	help_iptables_all -t mangle -A "$obj" -j MARK --set-mark 0/0x0000FF00
else
	if [ -n "$ebt_dscp_rule1" ]; then
		$ebt_dscp_rule1
		$ebt_dscp_rule2
		$ebt_dscp_rule3
		$ebt_dscp_rule4
		$ebt_dscp_rule5
		$ebt_dscp_rule6
		$ebt_dscp_rule7
		$ebt_dscp_rule8
	elif [ -n "$ebt_dscp_rule" ]; then
		$ebt_dscp_rule
	fi
fi
if [ "$newForwardingPolicy" = "256" ]; then
	rulemark="help_iptables_all -t $table -A $obj -j DROP"
elif [ -n "$newForwardingPolicy" ] && [ "$newForwardingPolicy" -gt 0 ]; then
	rulemark="help_iptables_all -t $table -A $obj -j MARK --set-mark $newForwardingPolicy/$newX_ADB_ForwardingPolicyMask"
fi
$rulemark
if [ "$newTrafficClass" != "-1" ]; then
	rulemark_qos="help_iptables_all -t $table -A $obj -j MARK --set-mark $((newTrafficClass * 16777216))/0xFF000000"
	$rulemark_qos
	if [ -n "$dscp_rule" ]; then
		$dscp_rule
	elif [ -n "$dscp_rule1" ]; then
		$dscp_rule1
		$dscp_rule2
		$dscp_rule3
		$dscp_rule4
		$dscp_rule5
		$dscp_rule6
		$dscp_rule7
		$dscp_rule8
	fi
	if [ -n "$vlan_rule" ]; then
		$vlan_rule
		if [ "$stage" = "OutputClasses" ] && [ -n "$vlan_rule1" ]; then
			$vlan_rule1
		fi
	elif [ -n "$vlan_rule1" ]; then
		$vlan_rule1
		$vlan_rule2
		$vlan_rule3
		$vlan_rule4
		$vlan_rule5
		$vlan_rule6
		$vlan_rule7
		$vlan_rule8
		$vlan_rule9
		$vlan_rule10
		$vlan_rule11
		$vlan_rule12
		$vlan_rule13
		$vlan_rule14
		$vlan_rule15
		$vlan_rule16
		$vlan_rule17
		$vlan_rule18
		$vlan_rule19
		$vlan_rule20
		$vlan_rule21
	fi
elif [ -n "$newApp" ] && [ "$newApp" != "-1" ]; then
	cmclient -v trafficclass GETV "$newApp".DefaultTrafficClass
	if [ -n "$dscp_rule" ]; then
		$dscp_rule
	elif [ -n "$dscp_rule1" ]; then
		$dscp_rule1
		$dscp_rule2
		$dscp_rule3
		$dscp_rule4
		$dscp_rule5
		$dscp_rule6
		$dscp_rule7
		$dscp_rule8
	fi
	if [ -n "$vlan_rule" ]; then
		$vlan_rule
		if [ "$stage" = "OutputClasses" ] && [ -n "$vlan_rule1" ]; then
			$vlan_rule1
		fi
	elif [ -n "$vlan_rule1" ]; then
		$vlan_rule1
		$vlan_rule2
		$vlan_rule3
		$vlan_rule4
		$vlan_rule5
		$vlan_rule6
		$vlan_rule7
		$vlan_rule8
		$vlan_rule9
		$vlan_rule10
		$vlan_rule11
		$vlan_rule12
		$vlan_rule13
		$vlan_rule14
		$vlan_rule15
		$vlan_rule16
		$vlan_rule17
		$vlan_rule18
		$vlan_rule19
		$vlan_rule20
		$vlan_rule21
	fi
	if [ -n "$newTrafficClass" ]; then
		rulemark_qos="help_iptables_all -t $table -A $obj -j MARK --set-mark $((trafficclass * 16777216))/0xFF000000"
	fi
	if [ "$newForwardingPolicy" = "256" ]; then
		rulemark="help_iptables_all -t $table -A $obj -j DROP"
	elif [ -n "$newForwardingPolicy" ]; then
		rulemark="help_iptables_all -t $table -A $obj -j MARK --set-mark $newForwardingPolicy/$newX_ADB_ForwardingPolicyMask"
	fi
	$rulemark
	$rulemark_qos
	cmclient -v helper_urn GETV "$newApp".ProtocolIdentifier
	helper=${helper_urn##*:}
	if [ -n "$helper" ]; then
		help_iptables_all -t "$table" -A $obj -j CONNMARK --set-mark 0x2/0x2
		help_iptables_all -t "$table" -A $obj -j HELPER --helper "$helper"
	fi
else
	if [ -n "$dscp_rule" ]; then
		$dscp_rule
	elif [ -n "$dscp_rule1" ]; then
		$dscp_rule1
		$dscp_rule2
		$dscp_rule3
		$dscp_rule4
		$dscp_rule5
		$dscp_rule6
		$dscp_rule7
		$dscp_rule8
	fi
	if [ -n "$vlan_rule" ]; then
		$vlan_rule
		if [ "$stage" = "OutputClasses" ] && [ -n "$vlan_rule1" ]; then
			$vlan_rule1
		fi
	elif [ -n "$vlan_rule1" ]; then
		$vlan_rule1
		$vlan_rule2
		$vlan_rule3
		$vlan_rule4
		$vlan_rule5
		$vlan_rule6
		$vlan_rule7
		$vlan_rule8
		$vlan_rule9
		$vlan_rule10
		$vlan_rule11
		$vlan_rule12
		$vlan_rule13
		$vlan_rule14
		$vlan_rule15
		$vlan_rule16
		$vlan_rule17
		$vlan_rule18
		$vlan_rule19
		$vlan_rule20
		$vlan_rule21
	fi
fi
if [ -n "$newPolicer" ]; then
	cmclient -v policer_enabled GETV "$newPolicer".Enable
	if [ "$policer_enabled" = "true" ]; then
		help_iptables -t "$table" -A "$obj" -j "$newPolicer"
	fi
fi
[ "$newX_ADB_Cascade" = "false" ] && help_iptables_all -t $table -A $obj -j ACCEPT
if [ "$init" != "1" ]; then
	i_list=""
	cmclient -v i GETV QoS.Queue.[Enable=true].Interface
	for i in $i; do
		help_is_in_list $i_list $i && continue
		[ ${#i_list} -gt 0 ] && i_list="$i_list,$i" || i_list="$i"
		cmclient -v i GETO "QoS.Queue.[Enable=true].[Interface=$i].[AllInterfaces=false]"
		[ ${#i} -gt 0 ] || continue
		set -- $i
		cmclient SET "$1".Enable true
	done
	cmclient -v i GETO QoS.Queue.[Enable=true].[AllInterfaces=true]
	if [ ${#i} -gt 0 ]; then
		set -- $i
		cmclient SET "$1".Enable true
	fi
fi
cmclient SET Device.X_ADB_FastForward.Yatta.FlushConnections true
if check_interface_in_hwswitch; then
	cmclient SET Device.Bridging.X_ADB_HWSwitch.DisableRequest Device.QoS.Classification
fi
exit 0
