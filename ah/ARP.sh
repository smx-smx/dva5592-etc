#!/bin/sh
AH_NAME="ARP"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_ipcalc.sh
getDestHost() {
	local IP_iface="$1" ret="$2" IPAddress="" SubnetMask="" gw
	cmclient -v gw GETV "Device.DHCPv4.Client.[Interface=$IP_iface].ReqOption.[Tag=3].Value"
	if [ ${#gw} -eq 0 ]; then
		cmclient -v IPAddress GETV "Device.DHCPv4.Client.[Interface=$IP_iface].IPAddress"
		[ ${#IPAddress} -ne 0 ] && cmclient -v SubnetMask GETV "Device.DHCPv4.Client.[Interface=$IP_iface].ReqOption.[Tag=1].Value"
		[ ${#SubnetMask} -ne 0 ] && help_first_ip "gw" "$IPAddress" "$SubnetMask"
	fi
	eval $ret="'$gw'"
}
stop_arping() {
	local iface="$1" pid
	if [ -e "/tmp/${AH_NAME}${iface}.ARP.pid" ]; then
		logger -t "cm" -p 4 "$AH_NAME stop probing test"
		read -r pid <"/tmp/${AH_NAME}${iface}.ARP.pid"
		kill $pid
		rm -f "/tmp/${AH_NAME}${iface}.ARP.pid"
	fi
}
start_arping() {
	local monitored_iface="$1" setm_params IP_iface nm ifaceOption destHost \
		countOption="-c 1" status arpOldStatus failSum arpFailureCount interval retries timer idx \
		qosOption tc
	stop_arping $monitored_iface
	cmclient -v IP_iface GETV "$monitored_iface.MonitoredInterface"
	if [ ${#IP_iface} -ne 0 ]; then
		help_lowlayer_ifname_get nm ${IP_iface}
		ifaceOption="-I $nm"
		cmclient -v tc GETV "Device.QoS.X_ADB_DefaultClassification.[Enable=true].[Protocols,ARP].TrafficClass"
		[ -n "$tc" ] && qosOption="-m $((tc * 16777216))"
		getDestHost "$IP_iface" "destHost"
		if [ ${#destHost} -eq 0 ]; then
			cmclient SETE "$monitored_iface.ARP.DiagnosticsState" "Error_Misconfigured"
			logger -t "cm" -p 4 "$AH_NAME misconfigured"
			cmclient -v idx ADDS "Device.X_ADB_Time.Event"
			timer="Device.X_ADB_Time.Event.$idx"
			setm_params="$timer.Alias=$monitored_iface.ARP.Enable"
			setm_params="$setm_params	$timer.Type=Aperiodic"
			setm_params="$setm_params	$timer.DeadLine=2"
			cmclient -v idx ADDS "$timer.Action"
			setm_params="$setm_params	$timer.Action.$idx.Operation=Set"
			setm_params="$setm_params	$timer.Action.$idx.Path=$monitored_iface.ARP.DiagnosticsState"
			setm_params="$setm_params	$timer.Action.$idx.Value=Request"
			cmclient SETEM "$setm_params"
			cmclient SET "$timer.Enable" "true"
			exit 0
		fi
		logger -t "cm" -p 4 "$AH_NAME start probing test"
		cmclient SETE "$monitored_iface.ARP.FailureCount" "0"
		arpOldStatus="$newDiagnosticsState"
		cmclient -v interval GETV "$monitored_iface.ARP.Interval"
		cmclient -v retries GETV "$monitored_iface.ARP.Retries"
		while true; do
			arping $ifaceOption $countOption $qosOption $destHost 2>&1
			status="$?"
			if [ "$status" = "0" ]; then
				failSum=0
			else
				cmclient -v arpFailureCount GETV "$monitored_iface.ARP.FailureCount"
				failSum=$((arpFailureCount + 1))
			fi
			cmclient SETE "$monitored_iface.ARP.FailureCount ${failSum}"
			if [ $failSum -ge "$retries" ]; then
				if [ "$arpOldStatus" != "Fail" ]; then
					logger -t "cm" -p 4 "$AH_NAME probing test fail"
					cmclient -u "${AH_NAME}${obj}" SET "$monitored_iface.ARP.DiagnosticsState" "Fail"
				fi
				arpOldStatus="Fail"
			elif [ $failSum -eq 0 ]; then
				if [ "$arpOldStatus" != "Complete" ]; then
					logger -t "cm" -p 4 "$AH_NAME probing test complete"
					cmclient -u "${AH_NAME}${obj}" SET "$monitored_iface.ARP.DiagnosticsState" "Complete"
				fi
				arpOldStatus="Complete"
			fi
			sleep $((interval - 1))
		done &
		echo "$!" >>/tmp/${AH_NAME}${monitored_iface}.ARP.pid
	else
		cmclient SETE "$monitored_iface.ARP.DiagnosticsState" "Error_Misconfigured"
	fi
}
service_config() {
	local iface
	case "$obj" in
	"Device.X_ADB_InterfaceMonitor.Group."*".Interface."*".ARP")
		if [ "$changedDiagnosticsState" = "1" ]; then
			iface=${obj%.ARP}
			case "$newDiagnosticsState" in
			"None")
				stop_arping $iface
				;;
			"Request")
				start_arping $iface
				;;
			esac
		fi
		;;
	esac
}
service_delete() {
	local iface
	case "$obj" in
	"Device.X_ADB_InterfaceMonitor.Group."*".Interface."*".ARP")
		iface=${obj%.ARP}
		stop_arping $iface
		;;
	esac
}
case "$op" in
s) service_config ;;
d) service_delete ;;
esac
exit 0
