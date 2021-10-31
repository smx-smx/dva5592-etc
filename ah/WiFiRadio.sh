#!/bin/sh
AH_NAME="WiFiRadio"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$user" = "NoWiFi" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_wlan.sh
. /etc/ah/target.sh
. /etc/ah/helper_PowerMng.sh
wifi_config_buffer_rates() {
	local rates_l="$2" buf="" v _v
	for v in $rates_l; do
		_v=${v%%.*}
		[ "$_v" = "$v" ] && rates="$(($v * 10))" || rates="$_v${v##*.}"
		[ -z "$buf" ] && buf="$rates" || buf="$buf $rates"
	done
	eval $1='$buf'
}
wifi_get_supported_rates() {
	local support="$2" basic_l="$3" basic_o buffer="" flag
	buffer="$basic_l"
	for support in $support; do
		flag="0"
		for basic_o in $basic_l; do
			if [ "$support" = "$basic_o" ]; then
				flag="1"
				break
			fi
		done
		[ "$flag" = "0" ] && buffer="$buffer $support"
	done
	eval $1='$buffer'
}
wifi_set_supported_rates() {
	local rates_v="$1" basic_l hostapd_v=""
	rates_v="$(help_tr "," " " "$rates_v")"
	basic_l="$wifi_basic_rates"
	if [ -n "$basic_l" ]; then
		basic_l="$(help_tr "," " " "$basic_l")"
		wifi_get_supported_rates hostapd_v "$rates_v" "$basic_l"
		wifi_config_buffer_rates hostapd_v "$hostapd_v"
		[ -n "$hostapd_v" ] && echo "supported_rates=$hostapd_v" >>$radioTempFile.$newName
	fi
}
wifi_set_basic_rates() {
	local rates_v="$1" hostapd_v=""
	rates_v="$(help_tr "," " " "$rates_v")"
	wifi_config_buffer_rates hostapd_v "$rates_v"
	[ -n "$hostapd_v" ] && echo "basic_rates=$hostapd_v" >>$radioTempFile.$newName
}
wifi_set_zwdfs() {
	local band="$1"
	case $band in
	'160MHz')
		cmclient SETE "Device.WiFi.Radio.[Name=$newName].X_ADB_ZeroWaitDFSEnable" 'false'
		;;
	*)
		cmclient SETE "Device.WiFi.Radio.[Name=$newName].X_ADB_ZeroWaitDFSEnable" 'true'
		;;
	esac
}
wifi_set_hw_mode() {
	local freq="$1" std="$2" band="$3" prim_channel="$4" ext_channel="$5" \
		nmode_protect="$6" tpc_mode="$7" e0rev938_reg_dom="$8" bsscoex htcap enable_n n_only ap _atf= acsd_auto_mode= \
		zwdfs_supported=
	if [ "$freq" = "5GHz" ]; then
		echo "hw_mode=a" >>$radioTempFile.$newName
		wifiradio_5g_settings $tpc_mode >>$radioTempFile.$newName
		cmclient -v acsd_auto_mode GETV Device.WiFi.Radio.[Name=$newName].AutoChannelEnable
		case $std in
		*"ac"*)
			echo "ieee80211ac=1" >>$radioTempFile.$newName
			[ "$std" = "ac" ] && echo "require_vht=1" >>$radioTempFile.$newName
			cmclient -v zwdfs_supported GETV "Device.WiFi.Radio.[Name=$newName].X_ADB_ZeroWaitDFSSupported"
			[ "$zwdfs_supported" = 'true' ] && wifi_set_zwdfs "$band"
			case $band in
			"20MHz" | "40MHz")
				echo "vht_oper_chwidth=0" >>$radioTempFile.$newName
				;;
			"80MHz")
				echo "vht_oper_chwidth=1" >>$radioTempFile.$newName
				;;
			"160MHz")
				if [ "$e0rev938_reg_dom" = "true" -a "$acsd_auto_mode" = "true" ]; then
					echo "vht_oper_chwidth=2" >>$radioTempFile.$newName
					[ $prim_channel -ne 0 ] &&
						echo "vht_oper_centr_freq_seg0_idx=50" >>$radioTempFile.$newName
				else
					cmclient SETE Device.WiFi.Radio.[Name=$newName].OperatingChannelBandwidth "80MHz"
					echo "vht_oper_chwidth=1" >>$radioTempFile.$newName
				fi
				;;
			*)
				[ "$band" = "Auto" ] &&
					echo "vht_oper_chwidth=1" >>$radioTempFile.$newName
				;;
			esac
			;;
		esac
	else
		case $std in
		"b")
			echo "hw_mode=b" >>$radioTempFile.$newName
			;;
		"g" | "g,n" | "n,g")
			echo "hw_mode=g" >>$radioTempFile.$newName
			wifi_set_gmode "true" "$wifi_gmode_protection"
			;;
		*)
			echo "hw_mode=g" >>$radioTempFile.$newName
			wifi_set_gmode "false" "$wifi_gmode_protection"
			;;
		esac
	fi
	case $std in
	*"n"* | *"ac"*)
		enable_n=1
		;;
	esac
	[ "$std" = "n" ] && n_only=1
	if [ -n "$enable_n" ]; then
		echo "ieee80211n=1" >>$radioTempFile.$newName
		case $band in
		"20MHz")
			htcap="[HT20]"
			;;
		*)
			if [ "$ext_channel" = "AboveControlChannel" ]; then
				htcap="[HT40+]"
			elif [ "$ext_channel" = "BelowControlChannel" ]; then
				htcap="[HT40-]"
			else
				case $prim_channel in
				"0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "36" | "44" | "52" | "60" | "100" | "108" | "124" | "132" | "149" | "157")
					htcap="[HT40+]"
					;;
				"8" | "9" | "10" | "11" | "12" | "13" | "40" | "48" | "56" | "64" | "104" | "112" | "120" | "128" | "136" | "153" | "161")
					htcap="[HT40-]"
					;;
				"116" | "140" | "165")
					htcap="[HT20]"
					;;
				esac
			fi
			;;
		esac
		[ -n "$htcap" ] && echo "ht_capab=$htcap" >>$radioTempFile.$newName
		[ -n "$n_only" ] && echo "nclients_only=1" >>$radioTempFile.$newName
		[ "$nmode_protect" = "true" ] &&
			echo "nmode_protection=-1" >>$radioTempFile.$newName || echo "nmode_protection=0" >>$radioTempFile.$newName
		wifiradio_set_stbc "$newName" "$wifi_stbc_rx" "$wifi_stbc_tx"
		wifiradio_get_hw_support "atf" && _atf="atf"
		case "${wifi_ampdu}-${wifi_atf}" in
		true-true) printf "ampdu=1${_atf:+\n$_atf=1}\n" ;;
		true-false) printf "ampdu=1${_atf:+\n$_atf=0}\n" ;;
		false-*) printf "ampdu=0${_atf:+\n$_atf=0}\n" ;;
		esac >>$radioTempFile.$newName
		case $band in
		"Auto")
			case "$wifi_std" in
			*ac*) bsscoex=0 ;;
			*n*) bsscoex=1 ;;
			*) bsscoex=0 ;;
			esac
			;;
		*)
			bsscoex="0"
			;;
		esac
		[ -n "$bsscoex" ] && echo "obss_coex=$bsscoex" >>$radioTempFile.$newName
	else
		echo "ieee80211n=0" >>$radioTempFile.$newName
	fi
}
wifi_set_channel() {
	local channel="$1" refresh="$2" dfs_rp="$3" lock_rp="$4"
	[ -n "$channel" ] && echo "channel=$channel" >>$radioTempFile.$newName
	[ -n "$refresh" ] && echo "autochannel_timer=$refresh" >>$radioTempFile.$newName
	[ -n "$dfs_rp" ] && echo "dfs_reentry_timer=$dfs_rp" >>$radioTempFile.$newName
	[ -n "$lock_rp" ] && echo "chanim_lockout_period=$lock_rp" >>$radioTempFile.$newName
	:
}
wifi_set_gmode() {
	local gonly="$1" protection="$2" confVal
	case $gonly in
	"true")
		confVal="1"
		[ -z "$protection" ] && protection="0"
		;;
	"false")
		confVal="0"
		[ -z "$protection" ] && protection="0"
		;;
	*)
		return
		;;
	esac
	echo "hw_mode_gonly=$confVal" >>$radioTempFile.$newName
	echo "gmode_protection=$protection" >>$radioTempFile.$newName
}
wifi_set_wmm() {
	{
		if [ "$wifi_wmm_enable" = "true" ]; then
			wifiradio_set_wmm enable
			[ "$wifi_wmm_noack" = "true" ] &&
				wifiradio_set_wmm_noack enable ||
				wifiradio_set_wmm_noack disable
		else
			wifiradio_set_wmm disable
			wifiradio_set_wmm_noack disable
		fi
	} >>$radioTempFile.$newName
}
wifi_enforce_extension_channel() {
	local _channel="$1" _autochn="$2" _extchn="$3" _req_extchn
	[ "$_autochn" = "true" -o "$_extchn" = "Auto" ] && return
	if [ "$wifi_freq" = "5GHz" ]; then
		case "$_channel" in
		"36" | "44" | "52" | "60" | "100" | "108" | "116" | "124" | "132" | "149" | "157")
			_req_extchn="AboveControlChannel"
			;;
		*)
			_req_extchn="BelowControlChannel"
			;;
		esac
	else
		if [ $_channel -lt 5 ]; then
			_req_extchn="AboveControlChannel"
		elif [ $_channel -gt 9 ]; then
			_req_extchn="BelowControlChannel"
		fi
	fi
	if [ -n "$_req_extchn" -a "$_req_extchn" != "$_extchn" ]; then
		cmclient -u "${AH_NAME}${obj}" SET "$obj.ExtensionChannel" "$_req_extchn"
		wifi_ext_channel="$_req_extchn"
	fi
}
wifi_align_channel() {
	local _channel="$1" _autochn="$2"
	if [ "$_channel" -le 14 ]; then
		cmclient SETE "$obj.OperatingFrequencyBand" "2.4GHz"
		wifi_freq="2.4GHz"
	else
		cmclient SETE "$obj.OperatingFrequencyBand" "5GHz"
		wifi_freq="5GHz"
	fi
	if [ "$_autochn" = "true" ]; then
		cmclient -u "${AH_NAME}${obj}" SET "$obj.AutoChannelEnable" "false"
		wifi_auto_chn_en="false"
	fi
}
service_do_enable_reconf() {
	local prim_channel
	[ "$wifi_auto_chn_en" = "true" ] && prim_channel="0" || prim_channel="$wifi_channel"
	cmclient -v acsdl GETV "Device.X_ADB_SystemLog.Service.[Identity=hostapd].Priority"
	case $acsdl in
	6)
		echo "acs_debug=5" >>$radioTempFile.$newName
		;;
	*) ;;

	esac
	wifi_set_hw_mode "$wifi_freq" "$wifi_std" "$wifi_n_band" "$prim_channel" "$wifi_ext_channel" "$wifi_nmode_protection" "$wifi_11hena" "$use_E0_938_reg_dom"
	[ "$wifi_auto_chn_en" = "true" ] && wifi_set_channel "0" "$wifi_auto_chn_rp" "$wifi_dfs_rp" "$wifi_auto_lock_pd" ||
		wifi_set_channel "$wifi_channel" "" 0
	wifi_set_wmm
	if [ -n "$wifi_country" -o -n "$use_E0_938_reg_dom" -a "$use_E0_938_reg_dom" = "true" ]; then
		if [ $WIFIRADIO_COUNTRY_USE_HOSTAPD = "true" ]; then
			[ "$use_E0_938_reg_dom" = "true" ] && echo "country_code=E0/938" >>$radioTempFile.$newName ||
				echo "country_code=$wifi_country" >>$radioTempFile.$newName
			echo "ieee80211d=1" >>$radioTempFile.$newName
		else
			wifiradio_set_country "$newName" "$wifi_country" "$use_E0_938_reg_dom"
		fi
	fi
	[ -n "$wifi_txpower" ] && wifiradio_set_txpower "$newName" "$wifi_txpower"
	[ -n "$wifi_basic_rates" ] && wifi_set_basic_rates "$wifi_basic_rates"
	[ -n "$wifi_support_rates" ] && wifi_set_supported_rates "$wifi_support_rates"
	[ -n "$wifi_bg_mrate" ] && echo "bg_mrate=$wifi_bg_mrate" >>$radioTempFile.$newName
	[ $wifi_max_sta -gt 0 ] && echo "max_num_sta_radio=$wifi_max_sta" >>$radioTempFile.$newName
	configure_power_mng "$newName" "$radioPowerMng"
	update_pcie_aspm_status $newName
	wifiradio_setup_tpid "$newName" $radioTempFile.$newName
	if [ ! -x "/usr/sbin/acsd" ]; then
		if [ $newAutoChannelEnable = "true" ]; then
			if [ "$newX_ADB_InterferenceAvoidance" = "true" ]; then
				echo "interference_avoiding=1" >>$radioTempFile.$newName
				[ -n "$newX_ADB_InterferenceAvoidanceThreshold" ] &&
					echo "chanim_acs_trigger=$newX_ADB_InterferenceAvoidanceThreshold" >>$radioTempFile.$newName
				[ -n "$newX_ADB_TxopBase" ] && echo "acs_txop_base=$newX_ADB_TxopBase" >>$radioTempFile.$newName
				[ -n "$newX_ADB_Inbss" ] && echo "acs_inbss=$newX_ADB_Inbss" >>$radioTempFile.$newName
			else
				echo "interference_avoiding=0" >>$radioTempFile.$newName
			fi
		fi
	fi
}
default_basic_rateset_config() {
	local OperatingStandards="$1" Frequency="$2" result_val="$3" rateset=""
	if [ "$Frequency" = "2.4GHz" ]; then
		case "$OperatingStandards" in
		"b")
			rateset="1,2"
			;;
		"g" | "g,n" | "n,g")
			rateset="6,12,24"
			;;
		*)
			rateset="1,2,5.5,11"
			;;
		esac
	elif [ "$Frequency" = "5GHz" ]; then
		rateset="6,12,24"
	fi
	eval $result_val="'$rateset'"
}
default_support_rateset_config() {
	local OperatingStandards="$1" Frequency="$2" result_val="$3" rateset=""
	if [ "$Frequency" = "2.4GHz" ]; then
		case "$OperatingStandards" in
		"b")
			rateset="1,2,5.5,11"
			;;
		"g" | "g,n" | "n,g")
			rateset="6,9,12,18,24,36,48,54"
			;;
		*)
			rateset="1,2,5.5,6,9,11,12,18,24,36,48,54"
			;;
		esac
	elif [ "$Frequency" = "5GHz" ]; then
		rateset="6,9,12,18,24,36,48,54"
	fi
	eval $result_val="'$rateset'"
}
rateset_filter() {
	local result_val="$1" newOperatingStandards="$2" wifi_rateset="$3" checked_rateset=""
	set -f
	IFS=','
	set -- $wifi_rateset
	unset IFS
	set +f
	for r; do
		case $newOperatingStandards in
		"b")
			case $r in
			1 | 2 | 5.5 | 11)
				checked_rateset=${checked_rateset:+$checked_rateset,}$r
				;;
			*) ;;

			esac
			;;
		"g" | "a" | "g,n" | "n,g" | "a,n" | "n,a")
			case $r in
			6 | 9 | 12 | 18 | 24 | 36 | 48 | 54)
				checked_rateset=${checked_rateset:+$checked_rateset,}$r
				;;
			*) ;;

			esac
			;;
		*) ;;

		esac
	done
	eval $result_val="'$checked_rateset'"
}
acsd_reconf() {
	[ -x "/usr/sbin/acsd" ] || return
	[ "$changedAutoChannelRefreshPeriod" = "1" ] &&
		acs_cli -i $newName acs_cs_scan_timer "$newAutoChannelRefreshPeriod"
	[ "$changedX_ADB_LockoutPeriod" = "1" ] &&
		acs_cli -i $newName set lockout_period "$newX_ADB_LockoutPeriod"
	if [ "$newX_ADB_InterferenceAvoidance" = "true" ]; then
		acs_cli -i $newName interference_avoiding "1"
		[ "$changedX_ADB_InterferenceAvoidanceThreshold" = "1" ] &&
			acs_cli -i $newName acs_trigger_var "$newX_ADB_InterferenceAvoidanceThreshold"
		[ "$changedX_ADB_TxopBase" = "1" ] &&
			acs_cli -i $newName acs_txop_base "$newX_ADB_TxopBase"
		[ "$changedX_ADB_Inbss" = "1" ] &&
			acs_cli -i $newName acs_inbss "$newX_ADB_Inbss"
	else
		acs_cli -i $newName interference_avoiding "0"
	fi
	[ "$changedAutoChannelEnable" = "1" -o "$changedOperatingChannelBandwidth" = "1" -o "$changedChannel" = "1" ] || return
	if [ "$newAutoChannelEnable" = "true" -o "$newOperatingChannelBandwidth" = "Auto" ]; then
		local c=0
		/etc/init.d/acsd.sh restart
		while [ $c -le 50 ]; do
			pidof acsd && break
			sleep 0.1
			c=$((c + 1))
		done
	else
		local enb
		cmclient -v enb GETO "Device.WiFi.Radio.[Enable=true].[AutoChannelEnable=true]"
		[ ${#enb} -eq 0 ] || cmclient -v enb GETO "Device.WiFi.Radio.[Enable=true].[OperatingChannelBandwidth=Auto]"
		[ ${#enb} -eq 0 ] && /etc/init.d/acsd.sh stop
	fi
}
service_reconf() {
	local _path="$1" _status="$2"
	service_do_enable_reconf "$_path" "$new_status"
	[ "$_status" != "Up" ] && cmclient -u "${AH_NAME}${_path}" SET "$_path.Status" "Up"
	cmclient SETE "$_path.X_ADB_ChannelSwitchReason" Init
	acsd_reconf
	wifi_config_start "true" "$newName" "$obj"
	case "$wifi_std" in
	*"ac"*) wifiradio_set_rate "$newName" "$wifi_mcs" "true" ;;
	*"n"*) wifiradio_set_rate "$newName" "$wifi_mcs" "false" ;;
	esac
	case "$wifi_freq" in
	*"5GHz"*) wifiradio_set_dhd_radarthrs "$newName" ;;
	esac
}
service_read() {
	wifi_freq="$newOperatingFrequencyBand"
	wifi_std="$newOperatingStandards"
	wifi_n_band="$newOperatingChannelBandwidth"
	wifi_ext_channel="$newExtensionChannel"
	wifi_nmode_protection="$newX_ADB_nProtection"
	wifi_supbw=""
	wifi_11hena="$newIEEE80211hEnabled"
	[ -n "$newRegulatoryDomain" ] && wifi_country=${newRegulatoryDomain%[I,O, ]}
	use_E0_938_reg_dom="$newX_ADB_UseE0Rev938RegulatoryDomain"
	wifi_channel="$newChannel"
	wifi_auto_chn_en="$newAutoChannelEnable"
	wifi_auto_chn_rp="$newAutoChannelRefreshPeriod"
	wifi_auto_lock_pd="$newX_ADB_LockoutPeriod"
	wifi_dfs_rp="$newX_ADB_DFSReentryTimer"
	[ "$setChannel" -eq 1 ] && wifi_align_channel "$wifi_channel" "$wifi_auto_chn_en"
	if [ "$setAutoChannelEnable" -eq 1 -a "$wifi_auto_chn_en" = "true" ]; then
		cmclient -v wifi_curbw GETV "$obj.OperatingFrequencyBand"
		cmclient -v wifi_supbw GETV "$obj.SupportedFrequencyBands"
		[ -z "$wifi_supbw" ] && wifi_supbw="2.4GHz"
		wifi_defbw=${wifi_supbw%,*}
		help_is_in_list "$wifi_supbw" "$wifi_curbw" && wifi_freq=$wifi_curbw || wifi_freq=$wifi_defbw
		cmclient SETE "$obj.OperatingFrequencyBand" "$wifi_freq"
	fi
	wifi_enforce_extension_channel "$wifi_channel" "$wifi_auto_chn_en" "$wifi_ext_channel"
	wifi_wmm_enable="$newX_ADB_WMMGlobalEnable"
	wifi_wmm_noack="$newX_ADB_WMMGlobalNoAck"
	[ "$newX_ADB_gmodeProtection" = "true" ] && wifi_gmode_protection="-1" || wifi_gmode_protection="0"
	wifi_mcs="$newMCS"
	wifi_txpower="$newTransmitPower"
	wifi_ampdu="$newX_ADB_AMPDU"
	wifi_atf=$newX_ADB_AirTimeFairnessEnable
	wifi_stbc_rx="$newX_ADB_STBC_Rx"
	wifi_stbc_tx="$newX_ADB_STBC_Tx"
	wifi_basic_rates="$newX_ADB_BasicDataTransmitRates"
	wifi_support_rates="$newX_ADB_OperationalDataTransmitRates"
	wifi_max_sta="$newX_ADB_MaxAssociatedDevices"
	rateset_filter wifi_basic_rates $newOperatingStandards $wifi_basic_rates
	rateset_filter wifi_support_rates $newOperatingStandards $wifi_support_rates
	[ -z "$wifi_basic_rates" ] && default_basic_rateset_config $newOperatingStandards $wifi_freq wifi_basic_rates
	[ -z "$wifi_support_rates" ] && default_support_rateset_config $newOperatingStandards $wifi_freq wifi_support_rates
	wifi_unii1_only="$newX_ADB_UNII1_ONLY"
}
service_get() {
	local obj="$1" arg="$2" wifi_ifname="$3" is_autoch
	case "$obj" in
	*"Stats"*)
		wifiradio_get_counters "$wifi_ifname" "$arg"
		;;
	*)
		case "$arg" in
		"Channel")
			cmclient -v is_autoch GETV "$obj.AutoChannelEnable"
			[ "$is_autoch" = "true" ] &&
				wifiradio_get_current_channel "$wifi_ifname" ||
				echo "$newChannel"
			;;
		"PossibleChannels")
			wifiradio_get_channel_list "$wifi_ifname" 52
			;;
		"ChannelsInUse")
			wifiradio_get_channels_in_use "$wifi_ifname"
			;;
		"X_ADB_MCSset")
			wifiradio_get_mcsset "$wifi_ifname"
			;;
		"X_ADB_VHT_MCSset")
			wifiradio_get_vht_mcsset "$wifi_ifname"
			;;
		"X_ADB_SupportedSpatialStreams")
			wifiradio_get_num_spatial_streams "$wifi_ifname"
			;;
		"X_ADB_CurrentExtensionChannel")
			wifiradio_get_ext_channel "$wifi_ifname"
			;;
		"MaxBitRate")
			wifiradio_get_max_bitrate "$wifi_ifname"
			;;
		LastChange)
			. /etc/ah/helper_lastChange.sh
			help_lastChange_get "$obj"
			;;
		*)
			echo ""
			;;
		esac
		;;
	esac
}
service_check() {
	local ch_list max
	if [ "$setChannel" -eq 1 ]; then
		[ "$user" = "force5Gchannel" ] || max=52
		ch_list=$(wifiradio_get_channel_list "$newName" $max)
		set -f
		IFS=','
		set -- $ch_list
		unset IFS
		set +f
		for ch; do
			[ "$ch" = "$newChannel" ] && return 0
		done
		return 1
	fi
	return 0
}
service_config() {
	[ -e "$radioTempFile.$newName" ] && rm -f $radioTempFile.$newName
	[ -e "$radioPowerMng.$newName" ] && rm -f $radioPowerMng.$newName
	service_check || exit 7
	[ "$setEnable" -eq 1 -a "$user" != "Time" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.X_ADB_ServiceActivated $newEnable"
	if [ "$user" = "boot" -o "$user" = "wifiradio_sched_start" ]; then
		service_init
		exit 0
	fi
	if [ $changedAutoChannelEnable -eq 1 -a $newAutoChannelEnable = "false" -a ${newChannel:-0} -ge 52 ]; then
		newChannel=36
	fi
	if [ "$changedEnable" -eq 1 -a "$newEnable" = "false" ]; then
		cmclient SET Device.WiFi.SSID.[LowerLayers=$obj].Stats.X_ADB_Reset "true"
		[ "$newStatus" != "Down" ] && cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "Down"
		wifi_stop "$newName" "$obj"
		wifi_align_status "false" "$newName" "$obj"
		update_pcie_aspm_status $newName
	elif [ "$changedEnable" -eq 1 -a "$newEnable" = "true" ]; then
		service_init
	elif [ "$newEnable" = "true" ]; then
		wifi_stop "$newName" "$obj"
		service_read
		service_reconf "$obj" "$newStatus"
	elif [ "$setChannel" -eq 1 ]; then
		wifi_auto_chn_en="$newAutoChannelEnable"
		wifi_align_channel "$newChannel" "$newAutoChannelEnable"
		wifi_enforce_extension_channel "$newChannel" "$wifi_auto_chn_en" "$newExtensionChannel"
	fi
	if [ "$newOperatingFrequencyBand" = "5GHz" -o "$newX_ADB_InterferenceOverride" -le 4 ]; then
		wifiradio_set_interference_override "$newName" "$newX_ADB_InterferenceOverride"
	else
		exit 7
	fi
}
service_init() {
	service_read
	service_do_enable_reconf "$obj" "$newStatus"
	cmclient -v ssid_path GETO "Device.WiFi.SSID.[LowerLayers=$obj].[Enable=true]"
	for ssid_path in $ssid_path; do
		cmclient -u boot SET "$ssid_path.Enable" "true"
		cmclient -v ap_path GETO "Device.WiFi.AccessPoint.[SSIDReference=$ssid_path].[Enable=true]"
		for ap_path in $ap_path; do
			cmclient -u boot SET "$ap_path.Enable" "true"
		done
	done
	cmclient -u "${AH_NAME}${obj}" SET "$obj.Status" "Up"
	cmclient SETE "$obj.X_ADB_ChannelSwitchReason" Init
	wifi_config_start "true" "$newName" "$obj"
	case "$wifi_std" in
	*"ac"*) wifiradio_set_rate "$newName" "$wifi_mcs" "true" ;;
	*"n"*) wifiradio_set_rate "$newName" "$wifi_mcs" "false" ;;
	esac
	case "$wifi_freq" in
	*"5GHz"*) wifiradio_set_dhd_radarthrs "$newName" ;;
	esac
}
case "$op" in
g)
	local radioName
	case "$obj" in
	*"Stats"*)
		obj_path="${obj%.*}"
		cmclient -v radioName GETV "$obj_path.Name"
		;;
	*)
		cmclient -v radioName GETV "$obj.Name"
		;;
	esac
	for arg; do # Arg list as separate words
		[ -n "$radioName" ] && service_get "$obj" "$arg" "$radioName" || echo ""
	done
	;;
s)
	service_config
	;;
esac
exit 0
