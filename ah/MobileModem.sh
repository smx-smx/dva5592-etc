#!/bin/sh
AH_NAME="Modem"
[ "$user" = "boot" ] && exit 0
[ "$user" = "${AH_NAME}" ] && exit 0
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
[ "$user" = "WWANModem" ] && exit 0
[ "$obj" = "Device.X_ADB_MobileModem.Interface.1" -a "$changedOperationStatus" = "1" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize ${AH_NAME}
. /etc/ah/helper_wwan.sh
while ! grep -q sysfs /proc/mounts; do
	sleep 2
done
manage_USBInterface() {
	local mmodem
	[ "$changedEnable" = "1" ] || return
	if [ "$newEnable" = "true" ]; then
		help_wwan_start ${WWAN_T}
	else
		help_wwan_stop ${WWAN_T}
		cmclient -u "$AH_NAME" SET $obj.Status "Down"
	fi
}
manage_EthernetLink() {
	local mmodem qsta ll
	if [ "$WWAN_T" = "at" ]; then
		help_wwan_start ${WWAN_T}
		return
	fi
	[ "$changedStatus" = 1 ] || return
	help_wwan_get_usbmodem mmodem
	cmclient -v ll GETV $obj.LowerLayers
	[ "$ll" = "$mmodem" ] || return
	cmclient -v qsta GETV ${mmodem}.Status
	if [ "${oldStatus}" = "Up" ]; then
		[ "$qsta" = "Up" ] || return
		help_wwan_stop ${WWAN_T}
		return
	fi
	if [ "${newStatus}" = "LowerLayerDown" ]; then
		[ "$qsta" != "Up" ] || return
		help_wwan_start ${WWAN_T}
		return
	fi
}
manage_PPPInterface() {
	[ "$WWAN_T" != "at" ] && return
	help_wwan_wwanmodem_reconf
}
manage_X_ADB_MobileModemSIMCard() {
	local mm_if pref_op qsta qrestart=""
	if [ "$setSIMOperator" = '1' -a "$newSIMOperator" != '' ]; then
		cmclient -v pref_op GETV "$obj".PreferredAPN
		pref_op=${pref_op%.APN*}
		[ -n "$pref_op" -a "$pref_op" != "$newSIMOperator" ] && cmclient SETE "$obj".PreferredAPN ''
	fi
	help_wwan_get_usbmodem "mm_if"
	. /etc/ah/wwan.sh
	[ "$changedPIN" = "1" ] && qrestart="true"
	if [ "$changedPINEnable" = "1" ]; then
		wwan_enablepin "$mm_if" "$obj" "$newPINEnable" "$newPIN" || exit 1
		qrestart="true"
	fi
	if [ "$changedPINChange" = "1" ]; then
		wwan_changepin "$mm_if" "$obj" "$newPIN" "$newNewPIN" || exit 1
		qrestart="true"
	fi
	if [ "$setPUK" = "1" -a -n "$newPUK" ]; then
		[ -n "$newPIN" ] || exit 1
		qrestart="true"
	fi
	if [ "$qrestart" = "true" ]; then
		cmclient -v qsta GETV ${mm_if}.Status
		[ "$qsta" = "Up" -a "$WWAN_T" != "at" ] && return
		help_wwan_start ${WWAN_T}
	fi
	help_wwan_wwanmodem_reconf
}
manage_X_ADB_MobileModemInterface() {
	local qsta
	[ "$changedEnable" = "1" ] || return
	if [ "$newEnable" = "true" ]; then
		help_wwan_start "$WWAN_T" "restart"
		return
	fi
	cmclient -v qsta GETV ${obj}.Status
	[ "$qsta" = "Up" ] || return
	help_wwan_stop "$WWAN_T"
}
manage_X_ADB_MobileModemOperator() {
	local operator proto
	[ "$WWAN_T" != "at" ] && return
	help_wwan_wwanmodem_reconf
	cmclient -v operator GETV X_ADB_MobileModem.Interface.1.ActiveOperator
	obj=${obj%%.APN*}
	[ "$obj" != "$operator" ] && return
	cmclient -v proto GETV "%(Device.X_ADB_MobileModem.Interface.1.Modem.ActiveModel).ModemInterfaceType"
	[ "$proto" != "SERIAL" ] && return
	cmclient -a -u "WWANModem" SET "PPP.Interface.[Status=Up].[LowerLayers=Device.X_ADB_MobileModem.Interface.1].Reset" "true"
	sleep 2
}
service_delete() {
	local mmodem msim moper aobj qsta
	case "$obj" in
	Device.X_ADB_MobileModem.Model.*)
		help_wwan_get_usbmodem mmodem
		cmclient -v aobj GETV "$mmodem".Modem.ActiveModel
		[ "$aobj" = "$obj" ] && cmclient SETE ${mmodem}.Modem.ActiveModel ''
		;;
	Device.X_ADB_MobileModem.SIMCard.*)
		help_wwan_get_usbmodem mmodem
		cmclient -v aobj GETV "$mmodem".ActiveSIMCard
		[ "$aobj" = "$obj" ] && cmclient SETE ${mmodem}.ActiveSIMCard ''
		;;
	Device.X_ADB_MobileModem.Operator.*.APN.*)
		cmclient -v msim GETO Device.X_ADB_MobileModem.SIMCard
		for msim in $msim; do
			cmclient -v aobj GETV "$msim".PreferredAPN
			[ "$aobj" = "$obj" ] && cmclient SETE "$msim".PreferredAPN ''
		done
		moper=${obj%.APN*}
		cmclient -v aobj GETV "$moper".DefaultAPN
		[ "$aobj" = "$obj" ] && cmclient SETE "$moper".DefaultAPN ''
		;;
	Device.X_ADB_MobileModem.Operator.*)
		help_wwan_get_usbmodem mmodem
		cmclient -v aobj GETV "$mmodem".ActiveOperator
		[ "$aobj" = "$obj" ] && cmclient SETE ${mmodem}.ActiveOperator ''
		cmclient -v msim GETO Device.X_ADB_MobileModem.SIMCard
		for msim in $msim; do
			cmclient -v aobj GETV "$msim".SIMOperator
			[ "$aobj" = "$obj" ] && cmclient SETE "$msim".SIMOperator ''
		done
		;;
	Device.X_ADB_MobileModem.Interface.*.Modem)
		obj=${obj%.Modem}
		cmclient -v qsta GETV ${obj}.Status
		if [ "$qsta" = Up ]; then
			local WWAN_T
			help_wwan_get_protocol "WWAN_T"
			help_wwan_stop "$WWAN_T"
		fi
		;;
	esac
}
service_config() {
	local OriginType
	if [ "$user" = "CWMP" ]; then
		OriginType="ACS"
	else
		OriginType="User"
	fi
	local WWAN_T
	help_wwan_get_protocol "WWAN_T"
	[ "$WWAN_T" != "at" -a "$user" = "InterfaceStack" ] && exit 0
	case "$obj" in
	Device.USB.Interface.*)
		manage_USBInterface
		;;
	Device.PPP.Interface.*)
		manage_PPPInterface
		;;
	Device.Ethernet.Link.*)
		manage_EthernetLink
		;;
	Device.X_ADB_MobileModem.SIMCard.*)
		manage_X_ADB_MobileModemSIMCard
		;;
	Device.X_ADB_MobileModem.Interface.*)
		manage_X_ADB_MobileModemInterface
		;;
	Device.X_ADB_MobileModem.Operator.*.APN.*)
		cmclient SETE $obj.Origin $OriginType
		cmclient SETE ${obj%.APN.*}.Origin $OriginType
		manage_X_ADB_MobileModemOperator
		;;
	Device.X_ADB_MobileModem.Operator.*)
		cmclient SETE $obj.Origin $OriginType
		manage_X_ADB_MobileModemOperator
		;;
	Device.X_ADB_MobileModem.Model.*)
		cmclient SETE $obj.Origin $OriginType
		;;
	esac
}
service_get() {
	local WWAN_T arg
	help_wwan_get_protocol "WWAN_T"
	if [ "$WWAN_T" = "at" ]; then
		for arg; do # Arg list as separate words
			eval "echo \$new$arg"
		done
	else
		. /etc/ah/wwan_get.sh
		wwan_handleget "$@"
	fi
}
service_add() {
	local OriginType
	if [ "$user" = "CWMP" ]; then
		OriginType="ACS"
	else
		OriginType="User"
	fi
	case "$obj" in
	Device.X_ADB_MobileModem.Operator.*.APN.*)
		cmclient SETE $obj.Origin $OriginType
		cmclient SETE ${obj%.APN.*}.Origin $OriginType
		;;
	Device.X_ADB_MobileModem.Operator.*)
		cmclient SETE $obj.Origin $OriginType
		;;
	Device.X_ADB_MobileModem.Model.*)
		cmclient SETE $obj.Origin $OriginType
		;;
	esac
}
case "$op" in
a)
	service_add
	;;
d)
	service_delete
	;;
g)
	service_get "$@"
	;;
s)
	service_config
	;;
esac
exit 0
