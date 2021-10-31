#!/bin/sh /etc/rc.common

exec 1>/dev/null
exec 2>/dev/null

START=13

. /etc/ah/helper_svc.sh

start() {
	local r sp ifnames chan fcs adfs bsah
	[ -f /tmp/acsd.conf ] && pidof acsd 1>/dev/null 2>&1 &&
		{
			echo "acsd is already running" >/dev/console
			return 0
		}
	cp /etc/wlan/acsd.conf /tmp/acsd.conf
	{
		cmclient -v ifnames GETV "WiFi.Radio.[Enable=true].[AutoChannelEnable=true].Name"

		cmclient -v r GETV "WiFi.Radio.[Enable=true].[AutoChannelEnable=false].[OperatingChannelBandwidth=Auto].[OperatingFrequencyBand=2.4GHz].Name"
		ifnames="$ifnames ""$r"

		for r in $r; do
			# Set prefered channel (only for Radio with AutoChannelEnable=false and OperatingChannelBandwidth=Auto):
			# - for channels equal or lower than 7 - set control channel lower than extension (0x1803 - 0x1809)
			# - for channels upper than 7 - set control channel upper than extension (0x1906 - 0x190b)
			cmclient -v chan GETV "WiFi.Radio.[Name=$r].Channel"
			[ $chan -le 7 ] && chan=$((chan + 0x1802)) || chan=$((chan + 0x18FE))
			printf "${r}_chanspec=0x%x\n" "$chan"
		done

		echo acs_ifnames=${ifnames}
		for r in $ifnames; do
			cmclient -v sp GETV "WiFi.Radio.[Name=$r].AutoChannelRefreshPeriod"
			[ $sp -gt 0 ] && echo "${r}_acs_cs_scan_timer=${sp}"
		done

		# Maybe in the future we will have multiple 5GHz radio...
		cmclient -v objs GETO "WiFi.Radio.[OperatingFrequencyBand=5GHz].[IEEE80211hEnabled=true]"
		for obj in $objs; do

			cmclient -v r GETV "$obj.Name"
			cmclient -v zwdfs GETV "$obj.X_ADB_ZeroWaitDFSEnable"

			echo ${r}_reg_mode=h
			if [ "$zwdfs" = 'true' ]; then
				echo ${r}_acs_fcs_mode=1
				echo ${r}_acs_bgdfs_ahead=1
				echo ${r}_acs_dfsr_timer=0
				echo ${r}_acs_dfs=2
			else
				echo ${r}_acs_fcs_mode=0
				echo ${r}_acs_bgdfs_ahead=0
				echo ${r}_acs_dfs=1
				cmclient -v sp GETV "$obj.X_ADB_DFSReentryTimer"
				echo ${r}_acs_dfsr_timer=${sp}
			fi
		done
		cmclient -v r GETV "WiFi.Radio.[OperatingFrequencyBand=2.4GHz].Name"
		for r in $r; do
			echo ${r}_acs_dfs=0
		done

		cmclient -v r GETV "WiFi.Radio.[X_ADB_InterferenceAvoidance=true].Name"
		for r in $r; do
			echo ${r}_interference_avoiding=1
			cmclient -v sp GETV "WiFi.Radio.[Name=$r].X_ADB_InterferenceAvoidanceThreshold"
			echo ${r}_acs_trigger_var="$sp"
			cmclient -v sp GETV "WiFi.Radio.[Name=$r].X_ADB_TxopBase"
			echo ${r}_acs_txop_base="$sp"
			cmclient -v sp GETV "WiFi.Radio.[Name=$r].X_ADB_Inbss"
			echo ${r}_acs_inbss="$sp"
		done

		cmclient -v r GETV "WiFi.Radio.[OperatingStandards~n].Name"
		for r in $r; do
			echo ${r}_nmode=-1
		done
	} >>/tmp/acsd.conf
	help_svc_start '/usr/sbin/acsd' 'acsd' 'daemon' '' 'echo failed starting ACSD >/dev/console' 15 '/tmp/acsd.pid'
}

stop() {
	help_svc_stop acsd
	rm -f /tmp/acsd.conf
}

restart() {
	stop
	start
}
