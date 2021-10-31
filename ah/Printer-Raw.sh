#!/bin/sh
[ "$user" = "yacs" ] && exit 0
[ "$user" = "boot" ] && exit 0
AH_NAME="Printer-Raw"
P910D_BASE_NAME="p"
P910D_BASE_PORT_NUM="9100"
P910D_SUFFIX="d"
service_reconf() {
local raw_status="Disabled" objs
cmclient -v lpPrnService GETV Device.Services.X_ADB_PrinterService.Enable
cmclient -v rawServer GETV Device.Services.X_ADB_PrinterService.Servers.RAW.Enable
if [ "$lpPrnService" = "true" ] && [ "$rawServer" = "true" ]; then
raw_status="Enabled"
cmclient -v objs GETO Device.Services.X_ADB_PrinterService.PrinterDevice.*.[Status=Online]
for printer in $objs; do
cmclient -v prnEnable GETV $printer.Enable
cmclient -v prnRawPortNum GETV $printer.RawPortNumber
cmclient -v prnDeviceName GETV $printer.DeviceName
if [ "$prnEnable" = "true" ] && [ -n "$prnRawPortNum" ] && [ -n "$prnDeviceName" ]; then
p910ndName=$P910D_BASE_NAME$prnRawPortNum$P910D_SUFFIX
pid=`pidof $p910ndName`
[ -n "$pid" ] && kill -9 $pid
prnRawPortNum=$((prnRawPortNum - $P910D_BASE_PORT_NUM))
p910nd -f $prnDeviceName $prnRawPortNum
[ $? -gt 0 ] && raw_status="Error"
fi
done
else
killall -9 p910nd
fi
cmclient SET "Device.Services.X_ADB_PrinterService.Servers.RAW.Status" "$raw_status"
}
service_config() {
[ "$changedEnable" = "1" -o "$setEnable" = "1" ] && service_reconf
}
case "$op" in
"s")
service_config
;;
esac
exit 0
