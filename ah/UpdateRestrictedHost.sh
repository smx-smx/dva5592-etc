#!/bin/sh
[ "$newUpdate" = false ] && exit 0
cmclient SET X_ADB_ParentalControl.RestrictedHosts.Update false >/dev/null
cmclient -v status GETV X_ADB_ParentalControl.RestrictedHosts.TimeOfDayEnabled
[ "$status" = "false" ] && exit 0
cmclient -v last_reset_day GETV X_ADB_ParentalControl.RestrictedHosts.LastReset
cur_day=$(date +%j)
if [ "$cur_day" -ne "$last_reset_day" ]; then
	cmclient SET X_ADB_ParentalControl.RestrictedHosts.Host.[Enable=true].[TypeOfRestriction=TIMEOFDAY].CurrentUsage 0 >/dev/null
	cmclient SET X_ADB_ParentalControl.RestrictedHosts.LastReset $cur_day >/dev/null
	cmclient SAVE &
fi
cmclient -v RO_MACS GETV X_ADB_ParentalControl.RestrictedHosts.Host.[Enable=true].[TypeOfRestriction=TIMEOFDAY].[Blocked=false].MACAddress
[ -z "$RO_MACS" ] && exit 0
for RO_MAC in $RO_MACS; do
	RO_IPS="$RO_IPS $(cmclient GETV Hosts.Host.[PhysAddress=$RO_MAC].[Active=true].IPAddress)"
done
[ -z "$RO_IPS" ] && exit 0
. /etc/ah/helper_restricted_host.sh
RO_HIT_FILE=/tmp/restricted_host_ips
cmclient -v WAN_IPS GETV IP.Interface.[X_ADB_Upstream=true].[Enable=true].IPv4Address.*.IPAddress
cmclient -v INTV GETV X_ADB_ParentalControl.RestrictedHosts.UsageInterval
INTV=$((INTV / 60))
MIN=$(date +%M)
MIN=${MIN#0}
if [ $INTV -lt 2 ]; then
	INTV=2
fi
while read -r a1 a2 a3 proto sec others; do
	set -- $others
	if [ "$proto" = "6" ]; then
		status=$1
		shift
	fi
	src_ip=${1##*=}
	dst_ip=${2##*=}
	if [ "$proto" = "1" ]; then
		shift 7
	else
		shift 6
	fi
	if [ "$1" = '[UNREPLIED]' ]; then
		shift
	fi
	rev_dst_ip=${2##*=}
	[ "$src_ip" = "$rev_dst_ip" ] && continue
	lookup $rev_dst_ip $WAN_IPS || continue
	lookup $src_ip $RO_IPS || continue
	tick="0"
	if [ "$status" = "ESTABLISHED" ]; then
		tick="1"
	elif [ $((INTV % 2)) -eq 0 ]; then
		tick="1"
	elif [ $((MIN % $INTV)) -ne 1 ]; then
		tick="1"
	elif [ $sec -gt 60 ]; then
		tick="1"
	else
		echo $src_ip >>$RO_HIT_FILE
	fi
	if [ $tick = "1" ]; then
		RO_HIT="$RO_HIT $src_ip"
	fi
done </proc/net/nf_conntrack
if [ $((MIN % $INTV)) -eq 0 ] || [ $((MIN % $INTV)) -eq 1 ]; then
	if [ -e $RO_HIT_FILE ]; then
		while read -r RO_IP; do
			lookup $RO_IP $RO_USED_IP && continue
			RO_USED_IP="$RO_USED_IP $RO_IP"
			cmclient -v RO_MACS GETV Hosts.Host.[IPAddress=$RO_IP].[Active=true].PhysAddress
			for RO_MAC in $RO_MACS; do
				cmclient -v USAGE GETV X_ADB_ParentalControl.RestrictedHosts.Host.[MACAddress=$RO_MAC].CurrentUsage
				cmclient SET X_ADB_ParentalControl.RestrictedHosts.Host.[MACAddress=$RO_MAC].CurrentUsage $((USAGE + $INTV * 60)) >/dev/null
				USAGE_UPDATED=1
			done
		done <$RO_HIT_FILE
	fi
	rm -f $RO_HIT_FILE
fi
[ "$USAGE_UPDATED" = "1" ] && cmclient SAVE &
for RO in $RO_HIT; do echo $RO >>$RO_HIT_FILE; done
