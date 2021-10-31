#!/bin/sh
AH_NAME="DslChannel"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_dsl.sh
. /etc/ah/helper_status.sh
STATS_NOVAL_LONG="18446744073709551615" # used as default value for u_long data type vars
STATS_NOVAL="4294967295"                # used as default value for u_int data type vars
service_reconf() {
	local _path="$1" _status="$2" _enable="$3" lls="$4" time lenc new_status
	[ -z "$lls" ] &&
		help_get_status_from_lowerlayers new_status "$_path" "$_enable" "$newLowerLayers" ||
		help_get_status_from_lowerlayers new_status "$_path" "$_enable" "$lls" true
	if [ "$new_status" = "Up" ]; then
		cmclient -v lenc GETV $_path.LinkEncapsulationUsed
		case "$lenc" in
		*"PTM")
			dsl_dev_exists atm && /etc/ah/ATMLink.sh del $_path
			;;
		*"ATM")
			dsl_dev_exists ptm && /etc/ah/PTMLink.sh del $_path
			;;
		esac
	fi
	cmclient SET -u "${AH_NAME}${_path}" "$_path.Status" "$new_status"
}
service_get() {
	local get_path="$1" ll
	case "$get_path" in
	*"UpstreamCurrRate")
		echo ${adsl_bearer_up_rate:-$STATS_NOVAL}
		;;
	*"DownstreamCurrRate")
		echo ${adsl_bearer_down_rate:-$STATS_NOVAL}
		;;
	*"LastChange")
		cmclient GETV "%($obj.LowerLayers).LastChange"
		;;
	*"INTLVDEPTH")
		echo ${adsl_down_d:-"0"}
		;;
	*"LPATH")
		. /etc/ah/target.sh
		help_get_dsl_vendor
		echo $adsl_latency_path
		;;
	*"INTLVBLOCK")
		echo ${adsl_down_i:-"-1"}
		;;
	*"ActualInterleavingDelay")
		echo ${adsl_down_delay:-"0"}
		;;
	*"ACTINP")
		if [ -n "$adsl_down_inp" ]; then
			echo ${adsl_down_inp%%.*}
		else
			echo "-1"
		fi
		;;
	*"INPREPORT")
		echo "false"
		;;
	*"NFEC")
		echo ${adsl_down_n:-"-1"}
		;;
	*"RFEC")
		echo ${adsl_down_r:-"-1"}
		;;
	*"LSYMB")
		echo ${adsl_down_l:-"-1"}
		;;
	*"Stats.PacketsReceived")
		if [ -n "$adsl_down_sf" ]; then
			echo $adsl_down_sf
		elif [ -n "$vdsl_down_sf" ]; then
			echo $vdsl_down_sf
		else
			echo $STATS_NOVAL_LONG
		fi
		;;
	*"Stats.PacketsSent")
		if [ -n "$adsl_up_sf" ]; then
			echo $adsl_up_sf
		elif [ -n "$vdsl_up_sf" ]; then
			echo $vdsl_up_sf
		else
			echo $STATS_NOVAL_LONG
		fi
		;;
	*"Stats.BytesReceived")
		if [ -n "$adsl_down_sf" -a -n "$adsl_down_b" ]; then
			echo $(($adsl_down_sf * 69 * $((adsl_down_b + 1))))
		elif [ -n "$vdsl_down_sf" -a -n "$adsl_down_b" ]; then
			echo $(($vdsl_down_sf * 257 * $((adsl_down_b + 1))))
		else
			echo
		fi
		;;
	*"Stats.BytesSent")
		if [ -n "$adsl_up_sf" -a -n "$adsl_up_b" ]; then
			echo $(($adsl_up_sf * 69 * $((adsl_up_b + 1))))
		elif [ -n "$vdsl_up_sf" -a -n "$adsl_down_b" ]; then
			echo $(($vdsl_up_sf * 257 * $((adsl_down_b + 1))))
		else
			echo
		fi
		;;
	*"Stats.ErrorsReceived")
		if [ -n "$adsl_down_sferr" ]; then
			echo $adsl_down_sferr
		elif [ -n "$vdsl_down_sferr" ]; then
			echo $vdsl_down_sferr
		else
			echo $STATS_NOVAL_LONG
		fi
		;;
	*"Stats.ErrorsSent")
		if [ -n "$adsl_up_sferr" ]; then
			echo $adsl_up_sferr
		elif [ -n "$vdsl_up_sferr" ]; then
			echo $vdsl_up_sferr
		else
			echo $STATS_NOVAL_LONG
		fi
		;;
	*"Stats.TotalStart")
		echo ${adsl_totalstart:-$STATS_NOVAL}
		;;
	*"Stats.ShowtimeStart")
		cmclient GETV "%(${obj%.*}.LowerLayers).Stats.ShowtimeStart"
		;;
	*"Stats.LastShowtimeStart")
		cmclient GETV "%(${obj%.*}.LowerLayers).Stats.LastShowtimeStart"
		;;
	*"Stats.CurrentDayStart")
		echo ${adsl_currentdaystart:-$STATS_NOVAL}
		;;
	*"Stats.QuarterHourStart")
		echo ${adsl_quarterhourstart:-$STATS_NOVAL}
		;;
	*"Stats.Total.XTURFECErrors")
		echo ${adsl_down_total_fec:-$STATS_NOVAL}
		;;
	*"Stats.Total.XTUCFECErrors")
		echo ${adsl_up_total_fec:-$STATS_NOVAL}
		;;
	*"Stats.QuarterHour.XTURFECErrors")
		echo ${adsl_down_quarterhour_fec:-$STATS_NOVAL}
		;;
	*"Stats.QuarterHour.XTUCFECErrors")
		echo ${adsl_up_quarterhour_fec:-$STATS_NOVAL}
		;;
	*"Stats.CurrentDay.XTURFECErrors")
		echo ${adsl_down_currentday_fec:-$STATS_NOVAL}
		;;
	*"Stats.CurrentDay.XTUCFECErrors")
		echo ${adsl_up_currentday_fec:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.XTURFECErrors")
		echo ${adsl_down_showtime_fec:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.XTUCFECErrors")
		echo ${adsl_up_currentday_fec:-$STATS_NOVAL}
		;;
	*"Stats.LastShowtime.XTURFECErrors")
		echo ${adsl_down_sincelastshowtime_fec:-$STATS_NOVAL}
		;;
	*"Stats.LastShowtime.XTUCFECErrors")
		echo ${adsl_up_sincelastshowtime_fec:-$STATS_NOVAL}
		;;
	*"Stats.Total.XTURCRCErrors")
		echo ${adsl_down_total_crc:-$STATS_NOVAL}
		;;
	*"Stats.Total.XTUCCRCErrors")
		echo ${adsl_up_total_crc:-$STATS_NOVAL}
		;;
	*"Stats.QuarterHour.XTURCRCErrors")
		echo ${adsl_down_quarterhour_crc:-$STATS_NOVAL}
		;;
	*"Stats.QuarterHour.XTUCCRCErrors")
		echo ${adsl_up_quarterhour_crc:-$STATS_NOVAL}
		;;
	*"Stats.CurrentDay.XTURCRCErrors")
		echo ${adsl_down_currentday_crc:-$STATS_NOVAL}
		;;
	*"Stats.CurrentDay.XTUCCRCErrors")
		echo ${adsl_up_currentday_crc:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.XTURCRCErrors")
		echo ${adsl_down_showtime_crc:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.XTUCCRCErrors")
		echo ${adsl_up_showtime_crc:-$STATS_NOVAL}
		;;
	*"Stats.LastShowtime.XTURCRCErrors")
		echo ${adsl_down_sincelastshowtime_crc:-$STATS_NOVAL}
		;;
	*"Stats.LastShowtime.XTUCCRCErrors")
		echo ${adsl_up_sincelastshowtime_crc:-$STATS_NOVAL}
		;;
	*"Stats.Total.XTURHECErrors")
		echo ${adsl_down_hec:-$STATS_NOVAL}
		;;
	*"Stats.Total.XTUCHECErrors")
		echo ${adsl_up_hec:-$STATS_NOVAL}
		;;
	*"Stats.QuarterHour.XTURHECErrors")
		echo ${adsl_down_hec:-$STATS_NOVAL}
		;;
	*"Stats.QuarterHour.XTUCHECErrors")
		echo ${adsl_up_hec:-$STATS_NOVAL}
		;;
	*"Stats.CurrentDay.XTURHECErrors")
		echo ${adsl_down_hec:-$STATS_NOVAL}
		;;
	*"Stats.CurrentDay.XTUCHECErrors")
		echo ${adsl_up_hec:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.XTURHECErrors")
		echo ${adsl_down_hec:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.XTUCHECErrors")
		echo ${adsl_up_hec:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.ES_U")
		echo ${adsl_up_showtime_es:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.ES_D")
		echo ${adsl_down_showtime_es:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.SES_U")
		echo ${adsl_up_showtime_ses:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.SES_D")
		echo ${adsl_down_showtime_ses:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.UAS_U")
		echo ${adsl_up_showtime_uas:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.UAS_D")
		echo ${adsl_down_showtime_uas:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.LOS_U")
		echo ${adsl_up_showtime_los:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.LOS_D")
		echo ${adsl_down_showtime_los:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.LOF_U")
		echo ${adsl_up_showtime_lof:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.LOF_D")
		echo ${adsl_down_showtime_lof:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.LOM_U")
		echo ${adsl_up_showtime_lom:-$STATS_NOVAL}
		;;
	*"Stats.Showtime.X_ADB_AdvancedStats.LOM_D")
		echo ${adsl_down_showtime_lom:-$STATS_NOVAL}
		;;
	*) ;;

	esac
}
service_config() {
	case "$obj" in
	Device.DSL.Channel.*)
		if [ "$changedStatus" = "1" ]; then
			return 0
		fi
		if [ "$changedEnable" = "1" ]; then
			service_reconf "$obj" "$newStatus" "$newEnable" ""
		fi
		;;
	*)
		if [ "$changedStatus" = "1" ]; then
			local lower_layer status_val enable_val
			cmclient -v lower_layer GETO "Device.DSL.Channel.[LowerLayers=$obj]"
			[ -z "$lower_layer" ] && exit
			cmclient -v status_val GETV "$lower_layer.Status"
			cmclient -v enable_val GETV "$lower_layer.Enable"
			service_reconf "$lower_layer" "$status_val" "$enable_val" "$newStatus"
		fi
		;;
	esac
}
case "$op" in
g)
	. /etc/ah/target.sh
	. /etc/ah/helper_dsl.sh
	help_get_dsl_stats
	for arg; do # Arg list as separate words
		service_get "$obj.$arg"
	done
	;;
s)
	service_config
	;;
esac
exit 0
