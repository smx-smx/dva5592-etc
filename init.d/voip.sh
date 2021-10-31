#!/bin/sh /etc/rc.common

exec 1>/dev/null
exec 2>/dev/null
. /etc/ah/helper_svc.sh

START=20

align_dect_versions() {
	local hw_ver sw_ver

	cmclient -v hw_ver GETV Device.DeviceInfo.HardwareVersion
	cmclient -v sw_ver GETV Device.DeviceInfo.SoftwareVersion

	[ -n "$hw_ver" ] &&
		cmclient SET "Device.Services.VoiceService.DECT.Base.1.HardwareVersion ${hw_ver}"

	[ -n "$sw_ver" ] &&
		cmclient SET "Device.Services.VoiceService.DECT.Base.1.FirmwareVersion ${sw_ver}"
}

probe_and_get_baudrate() {
	local _c

	# cleanup detection
	[ -f /tmp/serial_baud.log ] && rm /tmp/serial_baud.log

	cmbs_tcx -comspeed 57600 -probe

	[ -f /tmp/serial_baud.log ] ||
		cmbs_tcx -comspeed 115200 -probe

	[ -f /tmp/serial_baud.log ] || return

	read -r _c </tmp/serial_baud.log

	eval $1='$_c'
}

start() {
	# insert required modules
	local linux_ver=$(uname -r)
	local dect_calls alt_voice_params
	if [ -f /lib/modules/$linux_ver/endpointdd.ko ]; then
		# load broadcom modules if present
		if [ -f /lib/modules/$linux_ver/pcmshim.ko ]; then
			insmod pcmshim
		fi
		cmclient -v dect_calls GETV Device.X_SWISSCOM-COM_DeviceManagement.MaxNumberOfDECTCalls
		if [ "$dect_calls" = "4" ]; then
			echo 1 >/proc/brcm/alt_voice_params
		fi
		insmod endpointdd
	else
		# load mindspeed modules if present
		if [ -f /etc/init.d/tempo-slic ]; then
			[ -f /lib/modules/$linux_ver/common.ko ] && insmod common
			[ -f /etc/init.d/tempo-slic ] && /etc/init.d/tempo-slic start
			[ -f /lib/modules/$linux_ver/legerity_api.ko ] && insmod legerity_api
			[ -f /lib/modules/$linux_ver/legerity.ko ] && insmod legerity tdm_coding=1 slic_type=0,8 time_slot=0,0,0,1 flash_time=150
			# set address to interface versus second core
			ifconfig eth1 169.254.0.1
		fi
	fi
	[ -f /lib/modules/$linux_ver/yaps_dsp.ko ] && insmod yaps_dsp
	[ -f /lib/modules/$linux_ver/yaps_rtp.ko ] && insmod yaps_rtp

	# Reset Status (VoIP workaround objs)
	cmclient SET "Services.VoiceService.1.VoiceProfile.+.Line.[Enable=Enabled].Status" "Initializing"

	rm -f /etc/voip/*
	/etc/ah/VoIPService.sh r 1
	# echo "Starting VoIP application ..."
	killall -TERM voip

	(
		sleep 6
		if ! pidof voip; then
			start_voip=1
			cmclient -v voip_enable GETO Device.Services.VoiceService.*.[X_ADB_Enable=true]
			[ ${#voip_enable} -eq 0 ] && start_voip=0
			if [ $start_voip -gt 0 ]; then

				rm -f /tmp/voip.wd
				help_svc_start "voip >/dev/console" voip '' '' '' '15'

				# Wait voip startup
				while [ ! -f /var/run/voip.pid ]; do
					sleep 1
				done
			fi
		fi
	) &
}
