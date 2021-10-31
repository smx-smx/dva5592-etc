#!/bin/sh
AH_NAME="ATMDiagnostics"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_ifname.sh
. /etc/ah/target.sh
atmdiag_internal_error() {
	cmclient SETE "${obj}.DiagnosticsState" "Error_Internal"
	exit 0
}
atmdiag_perform_test() {
	local successCount=0 failureCount=0 AvgRspTimes=0 AvgRspTimema=0 AvgRspTimesb=0 AvgRspTimesc=0 diagState="Error_Other"
	local yapstimeout=${newTimeout:-5000}
	local _addr ll count xtm_portId name a
	cmclient -v _addr GETV "${newInterface}.DestinationAddress"
	cmclient -v ll GETV "${newInterface}.LowerLayers"
	cmclient -v xtm_portId GETV "${ll}.LPATH"
	xtm_portId=$((xtm_portId + 1))
	local xtm_vpi=${_addr%%/*} xtm_vci=${_addr##*/}
	count=1
	: ${newNumberOfRepetitions:=1}
	while [ $count -le $newNumberOfRepetitions ]; do
		set -f
		while IFS=" " read -r name a; do
			case "$name" in
			"XTM")
				failureCount=$(($failureCount + 1))
				;;
			"xtmctl:")
				successCount=$(($successCount + 1))
				;;
			"MinRspTime")
				if [ -z "$MinRspTime" ]; then
					MinRspTime=$a
				elif [ $MinRspTime -gt $a ]; then
					MinRspTime=$a
				fi
				;;
			"MaxRspTime")
				if [ -z "$MaxRspTime" ]; then
					MaxRspTime=$a
				elif [ $MaxRspTime -lt $a ]; then
					MaxRspTime=$a
				fi
				;;
			"AvgRspTime")
				AvgRspTimes=$((AvgRspTimes + $a))
				;;
			esac
		done <<-EOF
			$(xtm_send_oam "$xtm_portId.$xtm_vpi.$xtm_vci" f5end $yapstimeout)
		EOF
		set +f
		count=$((count + 1))
	done
	if [ $successCount -gt 0 ]; then
		AvgRspTimema=$(($AvgRspTimes / $successCount))
		AvgRspTimesb=$((($AvgRspTimes * 10) / $successCount))
		diagState="Complete"
	fi
	if [ $AvgRspTimema -gt 0 ]; then
		AvgRspTimesc=$(($AvgRspTimesb - ($AvgRspTimema * 10)))
		if [ "$(($AvgRspTimesc < 5))" = "0" ]; then
			AvgRspTimema=$(($AvgRspTimema + 1))
		fi
	fi
	AvgRspTime=$AvgRspTimema
	cmclient SETEM "${obj}.AverageResponseTime=$AvgRspTime	\
${obj}.MinimumResponseTime=$MinRspTime	${obj}.MaximumResponseTime=$MaxRspTime	\
${obj}.DiagnosticsState=$diagState	${obj}.SuccessCount=$successCount	\
${obj}.FailureCount=$failureCount"
	rm -f $pidfile
}
pidfile="/tmp/${AH_NAME}_${obj}.pid"
[ -e "$pidfile" ] && while read pid; do
	pkill -9 -P $pid
	kill $pid
done <$pidfile && rm -f $pidfile
if [ "$setDiagnosticsState" = "0" ] || [ "$newDiagnosticsState" != "Requested" ]; then
	cmclient SETE "${obj}.DiagnosticsState" "None"
	exit 0
fi
if [ -n "$newTimeout" -a "$newTimeout" -lt 200 ] || [ -z "$newInterface" ]; then
	atmdiag_internal_error
fi
help_lowlayer_ifname_get interfaceName "${newInterface}"
[ -z "$interfaceName" ] && atmdiag_internal_error
atmdiag_perform_test &
echo "$!" >>$pidfile
exit 0
