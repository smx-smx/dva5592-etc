#!/bin/sh
AH_NAME="NTP"
CHRONY_FILE="/tmp/chrony.conf"
TIME_ZONE_FILE="/tmp/TZ"
if [ "$op" = "s" -a "$changedStatus" = "1" ]; then
	case "$newStatus" in
	Synchronized)
		logger -t "cm" "NTP: time synch OK" -p 6
		if [ -x /usr/sbin/https_utils ]; then
			mkdir -p /tmp/cfg/httpd
			https_utils --generate-dh-params --outfile /tmp/cfg/httpd/dh.pkcs3 \
				--sec-param low --noout 30 >/dev/console
		fi
		;;
	Error_FailedToSynchronize)
		logger -t "cm" "NTP: time synch not OK" -p 6
		;;
	Error)
		logger -t "cm" "NTP: wrong config" -p 6
		;;
	esac
fi
[ "$newStatus" = "Synchronized" ] && cmclient SET Device.X_ADB_Time.Scheduler.Status Active || cmclient SET Device.X_ADB_Time.Scheduler.Status Not_Active
[ "$user" = "yacs" -o "$user" = "NTP" ] && exit 0
[ -f /tmp/upgrading.lock ] && [ "$op" != "g" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_svc.sh
reset_qos_classification() {
	local objs obj
	cmclient -v objs GETO Device.QoS.Classification.[Enable=true]
	for obj in $objs; do
		local chk leaf
		for leaf in X_ADB_DateStart X_ADB_DateStop X_ADB_TimeStart X_ADB_TimeStop; do
			cmclient -v chk GETV $obj.$leaf
			if [ -n "$chk" ]; then
				cmclient SET $obj.Enable true
				break
			fi
		done
	done
}
service_config() {
	local SETTINGS=""
	local SERVERS=""
	SETTINGS=" minpoll $newX_ADB_MinPoll maxpoll $newX_ADB_MaxPoll iburst"
	cat >$CHRONY_FILE <<"EOF"
logdir /var/log/
driftfile /tmp/chrony.drift
commandkey 24
allow 0/0
EOF
	if [ "$newX_ADB_Permissive" = "true" ]; then
		echo "local permissive stratum 8" >>$CHRONY_FILE
	else
		echo "local stratum 8" >>$CHRONY_FILE
	fi
	for i in 1 2 3 4 5; do
		eval ntph="\$newNTPServer${i}"
		if [ -n "$ntph" ]; then
			echo "server " $ntph "$SETTINGS" >>$CHRONY_FILE
			SERVERS="${SERVERS:+$SERVERS }$ntph"
		fi
	done
	echo "initstepslew 20 $SERVERS" >>$CHRONY_FILE
	echo "makestep 60 -1" >>$CHRONY_FILE
}
start_service() {
	[ ! -x /usr/sbin/chronyd ] && return 0
	[ "$newX_ADB_MaxPoll" -lt "$newX_ADB_MinPoll" ] && cmclient -u NTP SET Time.Status Error && return 0
	cmclient -u NTP SET Device.Time.Status Unsynchronized
	service_config
	OPTS="-n -f $CHRONY_FILE"
	if [ -f /tmp/ntp/loglevel ]; then
		read loglevel </tmp/ntp/loglevel && while [ $loglevel -gt 0 ]; do
			OPTS="$OPTS -d"
			loglevel=$((loglevel - 1))
		done
	fi
	echo "Starting NTP server"
	help_svc_start "chronyd $OPTS"
	reset_qos_classification
}
common_handle() {
	local ltime ltime_fmtutc
	[ "$setStatus" = "1" -a -e /tmp/ec_time/CheckRestrictedHost -a -x /etc/ah/CheckRestrictedHost.sh ] && /etc/ah/CheckRestrictedHost.sh
	if [ "$changedStatus" = "1" ]; then
		local firstUse
		cmclient -v firstUse GETV Device.DeviceInfo.FirstUseDate
		if [ -z "$firstUse" -o "$firstUse" = "0001-01-01T00:00:00Z" ]; then
			ltime="$(date -u +%FT%TZ)"
			cmclient SET "Device.DeviceInfo.FirstUseDate" "$ltime"
		fi
		return 0
	fi
	return 1
}
manual_handle() {
	date -s "$set_date $set_time"
	if [ "$newStatus" != "Synchronized" ]; then
		cmclient -u NTP SET "Device.Time.Status" "Synchronized"
		newStatus="Synchronized"
		changedStatus="1"
		setStatus="1"
	fi
	common_handle
	reset_qos_classification
}
ntp_handle() {
	common_handle
	if help_is_changed "Enable" "NTPServer1" "NTPServer2" "NTPServer3" \
		"NTPServer4" "NTPServer5" "X_ADB_MinPoll" "X_ADB_MaxPoll"; then
		help_svc_stop chronyd
		if [ "$newEnable" = "false" ]; then
			help_svc_stop chronyd
			cmclient -u NTP SET "Device.Time.Status" "Disabled"
			return 0
		fi
		start_service
	fi
}
handle_case="ntp"
if [ "$1" = "refresh" ]; then
	cmclient -v newEnable GETV Time.Enable
	[ "$newEnable" = "false" ] && exit 0
	help_svc_stop chronyd
	cmclient -v newNTPServer1 GETV Time.NTPServer1
	cmclient -v newNTPServer2 GETV Time.NTPServer2
	cmclient -v newNTPServer3 GETV Time.NTPServer3
	cmclient -v newNTPServer4 GETV Time.NTPServer4
	cmclient -v newNTPServer5 GETV Time.NTPServer5
	cmclient -v newNTPServer5 GETV Time.NTPServer5
	cmclient -v newLocalTimeZone GETV Time.LocalTimeZone
	cmclient -v newX_ADB_Permissive GETV Time.X_ADB_Permissive
	cmclient -v newX_ADB_MinPoll GETV Time.X_ADB_MinPoll
	cmclient -v newX_ADB_MaxPoll GETV Time.X_ADB_MaxPoll
	start_service
	exit 0
fi
if [ "$op" = "s" ]; then
	if [ "1" = "$setCurrentLocalTime" ]; then
		[ -z "$newCurrentLocalTime" -o "$newEnable" = "true" ] && exit 1
		set_date="${newCurrentLocalTime%%T*}"
		set_time="${newCurrentLocalTime##*T}"
		set_time=$(expr substr "$set_time" 1 8)
		[ "$changedEnable" = "1" ] && handle_case="ntp_manual" || handle_case="manual"
	fi
	if [ "$changedLocalTimeZone" = "1" ]; then
		echo "$newLocalTimeZone" >$TIME_ZONE_FILE
	fi
	case "$handle_case" in
	"ntp")
		ntp_handle
		;;
	"manual")
		manual_handle
		;;
	"ntp_manual")
		ntp_handle
		newStatus="Disabled"
		manual_handle
		;;
	esac
fi
exit 0
