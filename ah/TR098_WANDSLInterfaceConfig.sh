#!/bin/sh
[ "$user" = "cm181" ] && exit 0
source /etc/ah/helper_functions.sh
source /etc/ah/helper_tr098.sh
AH_NAME="WANDSLInterfaceConfig"
STATS_NOVAL_LONG="18446744073709551615" # used as default value for u_long data type vars
STATS_NOVAL="4294967295"                # used as default value for u_int data type vars
service_get() {
	local obj98="$1"
	local param98="$2"
	case $obj98 in
	*.Stats.Total)
		case $param98 in
		"FECErrors")
			paramval="${adsl_down_total_fec:-$STATS_NOVAL}"
			;;
		"ATUCFECErrors")
			paramval="${adsl_up_total_fec:-$STATS_NOVAL}"
			;;
		"HECErrors")
			paramval="${adsl_down_hec:-$STATS_NOVAL}"
			;;
		"ATUCHECErrors")
			paramval="${adsl_up_hec:-$STATS_NOVAL}"
			;;
		"CRCErrors")
			paramval="${adsl_down_total_crc:-$STATS_NOVAL}"
			;;
		"ATUCCRCErrors")
			paramval="${adsl_up_total_crc:-$STATS_NOVAL}"
			;;
		"ErroredSecs")
			paramval="${adsl_down_total_es:-$STATS_NOVAL}"
			;;
		"SeverelyErroredSecs")
			paramval="${adsl_down_total_ses:-$STATS_NOVAL}"
			;;
		"TransmitBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_up_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_up_sf:-$STATS_NOVAL}"
			fi
			;;
		"ReceiveBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_down_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_down_sf:-$STATS_NOVAL}"
			fi
			;;
		*)
			paramval=0
			;;
		esac
		;;
	*.Stats.Showtime)
		case $param98 in
		"FECErrors")
			paramval="${adsl_down_showtime_fec:-$STATS_NOVAL}"
			;;
		"ATUCFECErrors")
			paramval="${adsl_up_showtime_fec:-$STATS_NOVAL}"
			;;
		"HECErrors")
			paramval="${adsl_down_hec:-$STATS_NOVAL}"
			;;
		"ATUCHECErrors")
			paramval="${adsl_up_hec:-$STATS_NOVAL}"
			;;
		"CRCErrors")
			paramval="${adsl_down_showtime_crc:-$STATS_NOVAL}"
			;;
		"ATUCCRCErrors")
			paramval="${adsl_up_showtime_crc:-$STATS_NOVAL}"
			;;
		"ErroredSecs")
			paramval="${adsl_down_showtime_es:-$STATS_NOVAL}"
			;;
		"SeverelyErroredSecs")
			paramval="${adsl_down_showtime_ses:-$STATS_NOVAL}"
			;;
		"TransmitBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_up_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_up_sf:-$STATS_NOVAL}"
			fi
			;;
		"ReceiveBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_down_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_down_sf:-$STATS_NOVAL}"
			fi
			;;
		*)
			paramval=0
			;;
		esac
		;;
	*.Stats.LastShowtime)
		case $param98 in
		"FECErrors")
			paramval="${adsl_down_showtime_fec:-$STATS_NOVAL}"
			;;
		"ATUCFECErrors")
			paramval="${adsl_up_showtime_fec:-$STATS_NOVAL}"
			;;
		"HECErrors")
			paramval="${adsl_down_hec:-$STATS_NOVAL}"
			;;
		"ATUCHECErrors")
			paramval="${adsl_up_hec:-$STATS_NOVAL}"
			;;
		"CRCErrors")
			paramval="${adsl_down_showtime_crc:-$STATS_NOVAL}"
			;;
		"ATUCCRCErrors")
			paramval="${adsl_up_showtime_crc:-$STATS_NOVAL}"
			;;
		"ErroredSecs")
			paramval="${adsl_showtime_es:-$STATS_NOVAL}"
			;;
		"SeverelyErroredSecs")
			paramval="${adsl_showtime_ses:-$STATS_NOVAL}"
			;;
		"TransmitBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_up_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_up_sf:-$STATS_NOVAL}"
			fi
			;;
		"ReceiveBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_down_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_down_sf:-$STATS_NOVAL}"
			fi
			;;
		*)
			paramval=0
			;;
		esac
		;;
	*.Stats.CurrentDay)
		case $param98 in
		"FECErrors")
			paramval="${adsl_down_currentday_fec:-$STATS_NOVAL}"
			;;
		"ATUCFECErrors")
			paramval="${adsl_up_currentday_fec:-$STATS_NOVAL}"
			;;
		"HECErrors")
			paramval="${adsl_down_hec:-$STATS_NOVAL}"
			;;
		"ATUCHECErrors")
			paramval="${adsl_up_hec:-$STATS_NOVAL}"
			;;
		"CRCErrors")
			paramval="${adsl_down_currentday_crc:-$STATS_NOVAL}"
			;;
		"ATUCCRCErrors")
			paramval="${adsl_up_currentday_crc:-$STATS_NOVAL}"
			;;
		"ErroredSecs")
			paramval="${adsl_down_currentday_es:-$STATS_NOVAL}"
			;;
		"SeverelyErroredSecs")
			paramval="${adsl_down_currentday_ses:-$STATS_NOVAL}"
			;;
		"TransmitBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_up_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_up_sf:-$STATS_NOVAL}"
			fi
			;;
		"ReceiveBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_down_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_down_sf:-$STATS_NOVAL}"
			fi
			;;
		*)
			paramval=0
			;;
		esac
		;;
	*.Stats.QuarterHour)
		case $param98 in
		"FECErrors")
			paramval="${adsl_down_quarterhour_fec:-$STATS_NOVAL}"
			;;
		"ATUCFECErrors")
			paramval="${adsl_up_quarterhour_fec:-$STATS_NOVAL}"
			;;
		"HECErrors")
			paramval="${adsl_down_hec:-$STATS_NOVAL}"
			;;
		"ATUCHECErrors")
			paramval="${adsl_up_hec:-$STATS_NOVAL}"
			;;
		"CRCErrors")
			paramval="${adsl_down_quarterhour_crc:-$STATS_NOVAL}"
			;;
		"ATUCCRCErrors")
			paramval="${adsl_up_quarterhour_crc:-$STATS_NOVAL}"
			;;
		"ErroredSecs")
			paramval="${adsl_down_quarterhour_es:-$STATS_NOVAL}"
			;;
		"SeverelyErroredSecs")
			paramval="${adsl_down_quarterhour_ses:-$STATS_NOVAL}"
			;;
		"TransmitBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_up_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_up_sf:-$STATS_NOVAL}"
			fi
			;;
		"ReceiveBlocks")
			vdsl_up=$(cmclient GETV Device.IP.Interface.4.Status)
			if [ "$vdsl_up" != "Up" ]; then
				paramval="${adsl_down_sf:-$STATS_NOVAL}"
			else
				paramval="${vdsl_down_sf:-$STATS_NOVAL}"
			fi
			;;
		*)
			paramval=0
			;;
		esac
		;;
	*)
		paramval=$(cmclient GETV "$found_obj"."$param98")
		;;
	esac
	echo "$paramval"
}
case "$op" in
g)
	. /etc/ah/target.sh
	. /etc/ah/helper_dsl.sh
	help_get_dsl_stats
	found_obj=$(cmclient GETV "${obj%.Stats*}.X_ADB_TR181Name")
	if [ -n "$found_obj" ]; then
		for arg; do # Arg list as separate words
			service_get "$obj" "$arg"
		done
	else
		for arg; do # Arg list as separate words
			echo ""
		done
	fi
	;;
esac
exit 0
