#!/bin/sh
#nl:*,usb*,*
action=$OP
subsystem=$TYPE
devicename=$OBJ
. /etc/ah/helper_serialize.sh
case "$action" in
"add")
	pidof wwanmodem && exit 0
	cmclient -v cpe_status GETV Device.DeviceInfo.X_ADB_BootDone
	[ "$cpe_status" = "false" ] && exit 0
	help_serialize_run_once EH_USBMODEM "notrap"
	. /etc/ah/helper_wwan.sh && help_wwanmodem_start && sleep 1
	help_serialize_unlock EH_USBMODEM
	;;
"remove")
	[ -e /etc/ah/wwan.sh ] || exit 0
	. /etc/ah/helper_wwan.sh && help_wwan_get_protocol "proto"
	case "${devicename}${proto}" in
	"cdc-wdm"* | *"ecm")
		help_serialize_run_once EH_USBMODEM "notrap"
		. /etc/ah/wwan.sh
		wwan_remove "$proto"
		help_serialize_unlock EH_USBMODEM
		;;
	esac
	;;
esac
exit 0
