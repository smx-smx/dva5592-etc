#!/bin/sh
cups_status() {
	local objs status
	cmclient -v status GETV Services.X_ADB_PrinterService.Enable
	if [ "$status" = "false" ]; then
		echo Disabled
		return
	fi
	cmclient -v objs GETO Services.X_ADB_PrinterService.PrinterDevice.[Status=Online].[Enable=true]
	if [ ${#objs} -eq 0 ]; then
		echo "NoPrinters"
		return
	fi
	pidof cupsd >/dev/null 2>&1 && echo "Enabled" || echo "Error"
}
start_cups() {
	local objs
	cmclient -v objs GETO Services.X_ADB_PrinterService.PrinterDevice.[Status=Online].[Enable=true]
	if [ ${#objs} -eq 0 ]; then
		killall -9 cupsd
		return
	fi
	pidof cupsd && killall -s HUP cupsd || cupsd -c /tmp/cupsd/cupsd.conf
}
