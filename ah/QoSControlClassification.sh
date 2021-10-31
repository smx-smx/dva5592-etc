#!/bin/sh
AH_NAME="QoSControlClassification"
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_firewall.sh
control_traffic_config() {
	local i QueueTrafficClasses TrafficClasses queueObjVal queueObjList tcPrec=0 lowerPrec=2147483647 highClass=200 class_exists
	if [ -z "$newQueue" ]; then
		cmclient -v tcPrec GETV "Device.QoS.Queue.*.[Enable=true].Precedence"
		[ -n "$tcPrec" ] || exit 1
		set -- $tcPrec
		for i; do
			[ $i -lt $lowerPrec ] && lowerPrec=$i
		done
		QueueTrafficClasses="Device.QoS.Queue.[Precedence=${lowerPrec}].[Enable=true].TrafficClasses"
	else
		QueueTrafficClasses="${newQueue}.TrafficClasses"
	fi
	cmclient -v queueObjList GET "${QueueTrafficClasses}"
	set -- $queueObjList
	for i; do
		queueObjVal="$i"
		break
	done
	queueObj="${queueObjVal%;*}"
	TrafficClasses="${queueObjVal##*;}"
	while [ $highClass -le 255 ]; do
		if ! help_is_in_list "$TrafficClasses" $highClass; then
			cmclient -v class_exists GETV "Device.QoS.Classification.[TrafficClass=${highClass}].TrafficClass"
			[ -n "$class_exists" ] || break
		fi
		highClass=$((highClass + 1))
	done
	[ $highClass -gt 255 ] && exit 1
	cmclient SETE Device.QoS.X_ADB_DefaultClassification.TrafficClass "$highClass"
	[ -n "$TrafficClasses" ] && classSeparator=","
	cmclient SETE "${queueObj} ${TrafficClasses}${classSeparator}${highClass}"
	queueObj="${queueObjVal%.TrafficClasses*}"
	[ -n "$queueObj" -a "$user" != "conf_up" ] &&
		cmclient -u "${AH_NAME}" SET "${queueObj}.Enable true"
}
remove_class() {
	local l=$1 p=$2 i _rname _r
	eval _rname='$3'
	IFS=','
	set -- $l
	unset IFS
	for i; do
		[ "$i" = "$p" ] && continue
		[ -n "$_r" ] && _r="$_r,"
		_r="$_r$i"
	done
	eval $_rname='$_r'
}
flush_traffic_config() {
	local trafficClasses _trafficClasses trafficClassesPath queueObjVal
	cmclient SETE Device.QoS.X_ADB_DefaultClassification.TrafficClass "0"
	if [ -n "$oldQueue" ]; then
		trafficClassesPath="$oldQueue"
	else
		trafficClassesPath="Device.QoS.Queue.*.[TrafficClasses>$oldTrafficClass]"
	fi
	cmclient -v queueObjVal GET "${trafficClassesPath}.TrafficClasses"
	queueObj="${queueObjVal%;*}"
	trafficClasses="${queueObjVal##*;}"
	[ -n "$trafficClasses" ] && remove_class "$trafficClasses" "$oldTrafficClass" _trafficClasses
	cmclient SETE "${queueObj}" "${_trafficClasses}"
}
service_config() {
	[ -n "$newEnable" ] || exit 0
	if [ "$setEnable" = "1" -a "$newEnable" = "false" ]; then
		flush_traffic_config
		flush_default_classification
	fi
	if [ "$newEnable" = "true" ]; then
		flush_traffic_config
		control_traffic_config
		init_default_classification
	fi
}
arp_classification() {
	local mark="$1"
	echo "$mark" >/proc/sys/net/ipv4/conf/all/arp_mark
	ebtables -t broute -I "$dst" -p ARP -j mark --mark-set "$mark" --mark-target ACCEPT
}
dhcp_classification() {
	local mark="$1"
	ebtables -t broute -I "$dst" --ip-protocol UDP --ip-destination-port 67 -j mark --mark-set "$mark" --mark-target ACCEPT
	help_iptables -t "$table" -A "$dst" ! -p udp -j RETURN
	help_iptables -t "$table" -A "$dst" -p udp ! --destination-port 67 -j RETURN
	help_iptables -t "$table" -A "$dst" -j MARK --set-mark "${mark}/0xFF000000"
}
flush_default_classification() {
	local dc_status dst="ControlClassifications" stage="OutputClasses"
	cmclient -v dc_status GETV Device.QoS.X_ADB_DefaultClassification.Status
	[ "$dc_status" = "Disabled" ] && return
	ebtables -t broute -F "$dst" 2>/dev/null
	ebtables -t broute -D QoS.Classification -j "$dst" 2>/dev/null
	ebtables -t broute -X "$dst" 2>/dev/null
	help_iptables -t mangle -F "$dst"
	help_iptables -t mangle -D "$stage" -j "$dst"
	help_iptables -t mangle -X "$dst"
	cmclient SETE "Device.QoS.X_ADB_DefaultClassification.[Status!Disabled].Status Disabled"
	echo "0" >/proc/sys/net/ipv4/conf/all/arp_mark
}
init_default_classification() {
	local arp_tc_mark dhcp_tc_mark dst="ControlClassifications" table="mangle" stage="OutputClasses"
	flush_default_classification
	ebtables -t broute -N "$dst" -P RETURN
	ebtables -t broute -I QoS.Classification $pos -j "$dst"
	help_iptables -t "$table" -N "$dst"
	help_iptables -t "$table" -I "$stage" -j "$dst"
	cmclient -v arp_tc_mark GETV "Device.QoS.X_ADB_DefaultClassification.[Enable=true].[Protocols,ARP].TrafficClass"
	[ -n "$arp_tc_mark" ] && arp_classification $((arp_tc_mark * 16777216))
	cmclient -v dhcp_tc_mark GETV "Device.QoS.X_ADB_DefaultClassification.[Enable=true].[Protocols,DHCP].TrafficClass"
	[ -n "$dhcp_tc_mark" ] && dhcp_classification $((dhcp_tc_mark * 16777216))
	cmclient SETE "Device.QoS.X_ADB_DefaultClassification.[Status!Enabled].Status Enabled"
	exit 0
}
subOp="$1"
case "$subOp" in
init)
	init_default_classification
	;;
flush)
	flush_default_classification
	;;
*) ;;

esac
case "$op" in
s)
	service_config
	;;
esac
exit 0
