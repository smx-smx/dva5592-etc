#!/bin/sh
MODEMMNGR_NAME="wwanmodem"
MODEMMNGR_CMD="/sbin/$MODEMMNGR_NAME"
help_wwan_get_usbmodem() {
	eval $1="Device.X_ADB_MobileModem.Interface.1"
}
help_wwan_enable_swacc() {
	echo "add $1" >/proc/net/yatta/kdevs
}
help_wwan_get_protocol() {
	[ "$1" != "mtype" ] && local mtype
	[ "$1" != "wtype" ] && local wtype=""
	[ "$1" != "mmodem" ] && local mmodem
	help_wwan_get_usbmodem mmodem
	cmclient -v mtype GETV "%(${mmodem}.Modem.ActiveModel).ModemInterfaceType"
	case $mtype in
	SERIAL | HUAWEI_NCM)
		wtype=at
		;;
	QMI)
		[ -e /etc/ah/wwanmodem_qmi.sh ] || return 1
		wtype=qmi
		;;
	CDC_MBIM)
		[ -e /etc/ah/wwanmodem_mbim.sh ] || return 1
		wtype=mbim
		;;
	CDC_ECM)
		[ -e /etc/ah/wwanmodem_ecm.sh ] || return 1
		wtype=ecm
		;;
	*)
		eval $1='$mtype'
		return 1
		;;
	esac
	eval $1='$wtype'
}
help_wwan_checkproto() {
	[ "$1" != "proto" ] && local proto
	[ "$1" != "retval" ] && local retval=0
	help_wwan_get_protocol "proto"
	case "$proto" in
	"qmi") . /etc/ah/wwanmodem_qmi.sh ;;
	"mbim") . /etc/ah/wwanmodem_mbim.sh ;;
	"ecm") . /etc/ah/wwanmodem_ecm.sh ;;
	*) retval=1 ;;
	esac
	eval $1='$proto'
	return $retval
}
help_wwan_wwanmodem_reconf() {
	[ -x /tmp/ah/wwanmodem_reconf.sh ] && . /tmp/ah/wwanmodem_reconf.sh ||
		help_wwanmodem_start
}
help_wwan_wwanmodem_prepare() {
	pidof $MODEMMNGR_NAME && killall -USR2 $MODEMMNGR_NAME 2>/dev/null
}
help_wwanmodem_start() {
	local wan_usb usb_modem
	[ -x "$MODEMMNGR_CMD" ] || return
	if pidof $MODEMMNGR_NAME; then
		[ -d /tmp/usbmodem_exit ] && mv /tmp/usbmodem_exit /tmp/usbmodem_restart || return
	fi
	cmclient -v wan_usb GETO Device.USB.Interface.*.[Enable=true].[Upstream=true]
	for wan_usb in $wan_usb; do
		cmclient -v usb_modem GETO Device.X_ADB_MobileModem.Interface.*.[Enable=true].[LowerLayers=$wan_usb]
		for usb_modem in $usb_modem; do
			$MODEMMNGR_CMD >/dev/console 2>&1 &
			return
		done
	done
	return 1
}
help_wwan_prepare() {
	local proto=
	help_wwan_get_protocol proto
	[ -z "$proto" -o "$proto" = "at" ] && help_wwan_wwanmodem_prepare
}
help_wwan_start() {
	local mmodem proto=$1 cdname
	[ -z "$proto" ] && help_wwan_get_protocol proto
	if [ -z "$proto" -o "$proto" = "at" ]; then
		help_wwan_wwanmodem_reconf
		return
	fi
	help_wwan_get_usbmodem mmodem
	cmclient -v cdname GETV $mmodem.Name
	if [ -z "$cdname" ]; then
		help_wwan_wwanmodem_reconf
		return
	fi
	/etc/ah/wwan.sh wwan_start "restart"
}
help_wwan_stop() {
	local mmodem qsta proto=$1
	[ -z "$proto" ] && help_wwan_get_protocol proto
	if [ -z "$proto" -o "$proto" = "at" ]; then
		help_wwan_wwanmodem_reconf
		return
	fi
	help_wwan_get_usbmodem mmodem
	cmclient -v qsta GETV ${mmodem}.Status
	[ "$qsta" = "Up" ] || return
	/etc/ah/wwan.sh wwan_stop
}
