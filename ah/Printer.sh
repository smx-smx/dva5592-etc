#!/bin/sh
[ "$user" = "boot" ] && exit 0
. /etc/ah/helper_printer.sh
AH_NAME="PrinterDevice"
printers_conf() {
	local PRINTERS_CONF_FILE=/tmp/cupsd/printers.conf PRINTER_TMP_FILE=$(mktemp -p /tmp)
	local lpPrnService lpSpoolEnabled printer objs
	cmclient -v lpPrnService GETV Device.Services.X_ADB_PrinterService.Enable
	if [ "$lpPrnService" = "true" ]; then
		cmclient -v lpSpoolEnabled GETV Device.Services.X_ADB_PrinterService.SpoolEnabled
		cmclient -v objs GETO Device.Services.X_ADB_PrinterService.PrinterDevice.*.[Status=Online]
		for printer in $objs; do
			cmclient -v prnEnable GETV $printer.Enable
			cmclient -v prnName GETV $printer.Name
			cmclient -v prnDescription GETV $printer.Description
			cmclient -v prnLocation GETV $printer.Location
			cmclient -v prnDeviceURI GETV $printer.DeviceURI
			cmclient -v prnDeviceName GETV $printer.DeviceName
			if [ "$prnEnable" = "true" ]; then
				echo "<Printer $prnName>" >>$PRINTER_TMP_FILE
				echo "Info $prnDescription" >>$PRINTER_TMP_FILE
				echo "Location $prnLocation" >>$PRINTER_TMP_FILE
				echo "DeviceURI $prnDeviceURI" >>$PRINTER_TMP_FILE
				if [ "$lpSpoolEnabled" = "false" ]; then
					echo "DeviceFile $prnDeviceName" >>$PRINTER_TMP_FILE
				fi
				echo "State Idle" >>$PRINTER_TMP_FILE
				echo "Accepting  Yes" >>$PRINTER_TMP_FILE
				echo "Shared Yes" >>$PRINTER_TMP_FILE
				echo "JobSheets none none" >>$PRINTER_TMP_FILE
				echo "QuotaPeriod 0" >>$PRINTER_TMP_FILE
				echo "PageLimit 0" >>$PRINTER_TMP_FILE
				echo "KLimit 0" >>$PRINTER_TMP_FILE
				echo "OpPolicy default" >>$PRINTER_TMP_FILE
				echo "ErrorPolicy stop-printer" >>$PRINTER_TMP_FILE
				echo "</Printer>" >>$PRINTER_TMP_FILE
			fi
		done
	fi
	PRINTER_TMP_FILE_1=$(mktemp -p /tmp)
	egrep -v ",$" $PRINTER_TMP_FILE >$PRINTER_TMP_FILE_1
	mv $PRINTER_TMP_FILE_1 $PRINTERS_CONF_FILE
	rm $PRINTER_TMP_FILE
}
service_config() {
	printers_conf
	start_cups
}
case "$op" in
s)
	service_config
	;;
esac
exit 0
