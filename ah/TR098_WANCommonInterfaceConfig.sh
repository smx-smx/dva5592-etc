#!/bin/sh
[ "$user" = "cm181" ] && exit 0
. /etc/ah/helper_functions.sh
. /etc/ah/helper_tr098.sh
AH_NAME="TR098_WANCommonInterfaceConfig"
service_get() {
	local _param="$1"
	case "$_param" in
	"WANAccessType")
		if [ -n "$dslObj" ]; then
			echo "DSL"
		elif [ -n "$ethObj" ]; then
			echo "Ethernet"
		else
			echo ""
		fi
		;;
	"PhysicalLinkStatus")
		if [ -n "$dslObj" ]; then
			dslStatus=$(cmclient GETV "$dslObj.Status")
			case "$dslStatus" in
			"Up") echo "Up" ;;
			"Initializing") echo "Initializing" ;;
			*) echo "Down" ;;
			esac
		else
			ethStatus=$(cmclient GETV "$ethObj.Status")
			if [ "$ethStatus" = "Up" ]; then
				echo "Up"
			else
				echo "Down"
			fi
		fi
		;;
	"Layer1UpstreamMaxBitRate")
		if [ -n "$dslObj" ]; then
			. /etc/ah/target.sh
			. /etc/ah/helper_dsl.sh
			help_get_dsl_stats
			if [ -n "$adsl_max_up_rate" ]; then
				echo $(($adsl_max_up_rate * 1000))
			else
				echo ""
			fi
		else
			echo ""
		fi
		;;
	"Layer1DownstreamMaxBitRate")
		if [ -n "$dslObj" ]; then
			. /etc/ah/target.sh
			. /etc/ah/helper_dsl.sh
			help_get_dsl_stats
			if [ -n "$adsl_max_down_rate" ]; then
				echo $(($adsl_max_down_rate * 1000))
			else
				echo ""
			fi
		else
			echo ""
		fi
		;;
	"TotalBytesReceived")
		echo $rxbytes
		;;
	"TotalBytesSent")
		echo $txbytes
		;;
	"TotalPacketsReceived")
		echo $rxpackets
		;;
	"TotalPacketsSent")
		echo $txpackets
		;;
	esac
}
case "$op" in
g)
	wanDevice="${obj%.WANCommonInterfaceConfig*}"
	dslObj=$(cmclient GETO "$wanDevice.WANDSLInterfaceConfig")
	ethObj=$(cmclient GETO "$wanDevice.WANEthernetInterfaceConfig")
	rxbytes=0
	txbytes=0
	rxpackets=0
	txpackets=0
	for wanConn in $(cmclient GETO "$wanDevice.WANConnectionDevice"); do
		obj_link=$(cmclient GETO "$wanConn.WANDSLLinkConfig")
		[ -z "$obj_link" ] && obj_link=$(cmclient GETO "$wanConn.WANPTMLinkConfig")
		[ -z "$obj_link" ] && obj_link=$(cmclient GETO "$wanConn.WANEthernetLinkConfig")
		tr181obj=$(cmclient GETV "$obj_link.X_ADB_TR181Name")
		vid=$(cmclient GETV "$obj_link.X_ADB_VLANID")
		ifname=$(cmclient GETV "$tr181obj.Name")
		[ -z "$ifname" ] && continue
		[ -n "$vid" ] && ifname="${ifname}.${vid}"
		if [ -d /sys/class/net/"$ifname" ]; then
			rxbytes=$((rxbytes + $(cat /sys/class/net/"$ifname"/statistics/rx_bytes)))
			txbytes=$((txbytes + $(cat /sys/class/net/"$ifname"/statistics/tx_bytes)))
			rxpackets=$((rxpackets + $(cat /sys/class/net/"$ifname"/statistics/rx_packets)))
			txpackets=$((txpackets + $(cat /sys/class/net/"$ifname"/statistics/tx_packets)))
		else
			continue
		fi
	done
	for arg; do # Arg list as separate words
		service_get "$arg"
	done
	;;
esac
exit 0
