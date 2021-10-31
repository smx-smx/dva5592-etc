#!/bin/sh
AH_NAME="QoSQueueStats"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
get_qos_queue() {
	local queue hnd
	if [ "${obj%.*}" = "Device.QoS.QueueStats" ]; then
		cmclient -v queue GETV "$obj".Status
		[ "$queue" != "Enabled" ] && return
		cmclient -v queue GETV "$obj".Queue
	else
		queue=$obj
	fi
	cmclient -v hnd GETV "$queue".X_ADB_Handle
	set -f
	set -- $(tc -s qdisc show dev "${hnd% *}" | grep -A2 "parent ${hnd#* }")
	set +f
	case "$2" in
	lbfifo)
		OutputPackets="${11}"
		OutputBytes="${9}"
		DroppedPackets="${16}"
		BufferLength="${19}"
		DroppedBytes="${14}"
		QueueOccupancyPackets="${27%p}"
		if [ "${19}" != "0" ]; then
			size="${19%b}"
			backlogBytes="${26%b}"
			backlogBytes100="$((backlogBytes * 100))"
			qop="$((backlogBytes100 / size))"
			if [ $qop -gt 100 ]; then
				QueueOccupancyPercentage="100"
			else
				QueueOccupancyPercentage="$((backlogBytes100 / size))"
			fi
		fi
		;;
	red)
		OutputPackets="${16}"
		OutputBytes="${14}"
		DroppedPackets="${24}"
		BufferLength="${7%b}"
		DroppedBytes="${19}"
		QueueOccupancyPackets="${32%p}"
		if [ "${7%b}" != "0" ]; then
			size="${7%b}"
			backlogBytes="${32%p}"
			backlogBytes100="$((backlogBytes * 150000))"
			qop="$((backlogBytes100 / size))"
			if [ $qop -gt 100 ]; then
				QueueOccupancyPercentage="100"
			else
				QueueOccupancyPercentage="$((backlogBytes100 / size))"
			fi
		fi
		;;
	esac
}
case "$op" in
g)
	case "$obj" in
	"InternetGatewayDevice."*)
		cmclient -v obj GETV "$obj.X_ADB_TR181Name"
		;;
	esac
	get_qos_queue
	for arg; do # Arg list as separate words
		eval echo \"\${$arg-0}\"
	done
	;;
s)
	[ "$changedEnable" = "0" -a "$changedInterface" = "0" -a "$changedQueue" = "0" ] && exit 0
	[ "$changedEnable" = "1" -a "$newEnable" = "false" ] &&
		cmclient SETE "$obj".Status Disabled
	[ "$newEnable" = "true" ] || exit 0
	cmclient -v tmp GETO "$newQueue"
	[ ${#newQueue} -eq 0 -o ${#tmp} -eq 0 ] &&
		cmclient SETE "$obj".Status Error ||
		cmclient SETE "$obj".Status Enabled
	;;
esac
exit 0
