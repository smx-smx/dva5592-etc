#!/bin/sh
[ "$user" = "yacs" ] && exit 0
[ -f /tmp/upgrading.lock ] && [ "$op" != "g" ] && exit 0
. /etc/ah/helper_printer.sh
AH_NAME="CUPS"
printers_conf() {
local objs PRINTER_TMP_FILE=`mktemp -p /tmp` PRINTERS_CONF_FILE=/tmp/cupsd/printers.conf
mkdir -p /tmp/cupsd
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
PRINTER_TMP_FILE_1=`mktemp -p /tmp`
egrep -v ",$" $PRINTER_TMP_FILE > $PRINTER_TMP_FILE_1
mv $PRINTER_TMP_FILE_1 $PRINTERS_CONF_FILE
rm $PRINTER_TMP_FILE
}
service_reconf() {
local objs TMP_FILE=`mktemp -p /tmp` CUPSSPOOL="/cups-spool" CUPS_CONF_FILE=/tmp/cupsd/cupsd.conf
cmclient -v lpSpoolEnabled GETV Device.Services.X_ADB_PrinterService.SpoolEnabled
if [ "$lpSpoolEnabled" = "true" ]; then
cmclient -v lpSpoolDirectory GETV Device.Services.X_ADB_PrinterService.SpoolPartition
cmclient -v lpSpoolDirectory GETV $lpSpoolDirectory.Name
lpSpoolDirectory=`basename $lpSpoolDirectory`
lpSpoolDirectory=/mnt/$lpSpoolDirectory
lpSpoolDirectory=$lpSpoolDirectory$CUPSSPOOL
else
lpSpoolDirectory=/var/cups
fi
[ ! -e $lpSpoolDirectory/tmp ] && mkdir -m a+rwxt -p $lpSpoolDirectory/tmp
cat > $TMP_FILE <<EOF
AccessLog syslog
ErrorLog syslog
LogLevel info
PageLog syslog
PreserveJobHistory No
PreserveJobFiles No
AutoPurgeJobs Yes
MaxJobs 25
MaxPrinterHistory 10
RequestRoot ${lpSpoolDirectory}
RIPCache 512k
TempDir ${lpSpoolDirectory}
Listen localhost:631
HostNameLookups Off
KeepAlive On
Browsing On
BrowseProtocols cups
EOF
cmclient -v ippEnable GETV "Device.Services.X_ADB_PrinterService.Servers.IPP.Enable"
if [ "$ippEnable" = "true" ]; then
cmclient -v prnInterfaces GETV "Device.Services.X_ADB_PrinterService.Interfaces"
if [ -z "$prnInterfaces" ]; then
cmclient -v objs GETO Device.IP.Interface.[X_ADB_Upstream=false]
for ipObj in $objs
do
[ -z "$prnInterfaces" ] && prnInterfaces="$ipObj" || prnInterfaces="$prnInterfaces,$ipObj"
done
fi
cmclient -v ippPort GETV "Device.Services.X_ADB_PrinterService.Servers.IPP.Port"
IFS=','
set -- $prnInterfaces
unset IFS
for ipObj; do
cmclient -v objs GETO $ipObj.IPv4Address.[Enable=true].[IPAddress!]
for ipAddrObj in $objs; do
cmclient -v ipAddress GETV "$ipAddrObj.IPAddress"
cat >> $TMP_FILE <<EOF
Listen ${ipAddress}:${ippPort}
EOF
done
done
fi
cat >> $TMP_FILE <<EOF
<Location />
AuthType None
AuthClass Anonymous
</Location>
<Location /admin>
Order allow,deny
</Location>
<Location /admin/conf>
Order allow,deny
</Location>
<Policy default>
<Limit CUPS-Add-Modify-Printer CUPS-Delete-Printer CUPS-Add-Modify-Class CUPS-Delete-Class CUPS-Set-Default CUPS-Get-Devices>
Order allow,deny
</Limit>
<Limit All>
Order deny,allow
</Limit>
</Policy>
EOF
TMP_FILE_1=`mktemp -p /tmp`
egrep -v ",$" $TMP_FILE > $TMP_FILE_1
mv $TMP_FILE_1 $CUPS_CONF_FILE
rm $TMP_FILE
printers_conf
}
service_config() {
if [ "$changedEnable" = "1" ] || [ "$setEnable" = "1" ] || \
[ "$changedInterfaces" = "1" ] || [ "$setInterfaces" = "1" ]; then
killall -9 cupsd
if [ "$newEnable" = "true" ]; then
service_reconf
start_cups
fi
else
cmclient -v cupsEnable GETV Device.Services.X_ADB_PrinterService.Enable
if [ "$cupsEnable" = "true" ]; then
service_reconf
start_cups
fi
fi
}
service_get() {
case $1 in 
Status)
cups_status
;;
*)
echo ""
;;
esac
}
case "$op" in
"s")
service_config
;;
"g")
for arg # Arg list as separate words
do
service_get "$arg"
done
;;
esac
exit 0
