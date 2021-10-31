#!/bin/sh
AH_NAME="Printer-Raw"
P910D_BASE_NAME="p"
P910D_BASE_PORT_NUM="9100"
P910D_SUFFIX="d"
service_reconf() {
	if [ "$newEnable" = "true" ]; then
		cmclient -v lpPrnService GETV Device.Services.X_ADB_PrinterService.Enable
		if [ "$lpPrnService" = "true" ]; then
			cmclient -v prnEnable GETV $obj.Enable
			cmclient -v prnRawPortNum GETV $obj.RawPortNumber
			cmclient -v prnDeviceName GETV $obj.DeviceName
			if [ "$prnEnable" = "true" ] && [ -n "$prnRawPortNum" ] && [ -n "$prnDeviceName" ]; then
				p910ndName=$P910D_BASE_NAME$prnRawPortNum$P910D_SUFFIX
				pid=$(pidof $p910ndName)
				[ -n "$pid" ] && kill -9 $pid
				prnRawPortNum=$((prnRawPortNum - $P910D_BASE_PORT_NUM))
				p910nd -f $prnDeviceName $prnRawPortNum &
			fi
		fi
	else
		cmclient -v rpnVal GETV $lpRaw.RawPortNumber
		if [ -n "$rpnVal" ]; then
			p910ndName=$P910D_BASE_NAME$rpnVal$P910D_SUFFIX
			pid=$(pidof $p910ndName)
			[ -n "$pid" ] && kill -9 $pid
		fi
		killall -9 p910nd
	fi
}
service_config() {
	[ "$changedEnable" = "1" ] && service_reconf
}
case "$op" in
s)
	service_config
	;;
esac
exit 0
